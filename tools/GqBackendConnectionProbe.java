import com.google.gson.*;
import edu.sc.seis.seisFile.mseed.DataRecord;
import globalquake.core.GlobalQuake;
import globalquake.core.database.*;
import globalquake.core.exception.ApplicationErrorHandler;
import globalquake.core.station.GlobalStation;
import gqserver.api.packets.station.InputType;
import gqserver.server.GlobalQuakeServer;
import java.nio.file.*;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.atomic.AtomicLong;

/** Original GQ server and SeedlinkNetworksReader; only the record consumer counts. */
public class GqBackendConnectionProbe {
    static final Gson JSON = new Gson();
    static final AtomicLong records = new AtomicLong();
    static final AtomicLong firstRecordAt = new AtomicLong();
    static class CountedStation extends GlobalStation {
        volatile long latestEnd = Long.MIN_VALUE;
        volatile long received = 0;
        CountedStation(JsonObject e, int id, SeedlinkNetwork source) {
            super(e.get("network").getAsString(), e.get("station").getAsString(),
                channel(e), location(e), e.get("latitude").getAsDouble(),
                e.get("longitude").getAsDouble(), e.get("elevation").getAsDouble(),
                id, source, e.get("sensitivity").getAsDouble(), inputType(e));
        }
        static String channel(JsonObject e) {
            String selector = e.get("selector").getAsString();
            return selector.substring(selector.length() - 5, selector.length() - 2);
        }
        static String location(JsonObject e) {
            String selector = e.get("selector").getAsString();
            return selector.substring(0, selector.length() - 5);
        }
        static InputType inputType(JsonObject e) {
            String units = e.getAsJsonArray("metadataRow").get(13).getAsString().toUpperCase(Locale.ROOT);
            return switch (units) {
                case "M/S" -> InputType.VELOCITY;
                case "M/S**2", "M/S^2" -> InputType.ACCELERATION;
                case "M" -> InputType.DISPLACEMENT;
                default -> InputType.UNKNOWN;
            };
        }
        @Override public void addRecord(DataRecord record) {
            long end = record.getLastSampleBtime().toInstant().toEpochMilli();
            latestEnd = Math.max(latestEnd, end);
            received++;
            records.incrementAndGet();
            firstRecordAt.compareAndSet(0, System.currentTimeMillis());
        }
    }
    public static void main(String[] args) throws Exception {
        // input, isolated data directory, seconds after RUNNING, maximum handshake seconds
        Path input = Path.of(args[0]);
        Path directory = Path.of(args[1]);
        Files.createDirectories(directory);
        JsonObject spec = JsonParser.parseString(Files.readString(input)).getAsJsonObject();
        GlobalQuake.prepare(directory.toFile(), new ApplicationErrorHandler(null, true));
        StationDatabase db = new StationDatabase();
        db.getNetworks().clear();
        db.getSeedlinkNetworks().clear();
        db.getStationSources().clear();
        int connections = args.length > 4 ? Integer.parseInt(args[4]) : 1;
        if (connections < 1 || connections > 3) throw new IllegalArgumentException("Use 1 to 3 diagnostic connections");
        List<SeedlinkNetwork> sources = new ArrayList<>();
        for (int i = 0; i < connections; i++) {
            SeedlinkNetwork source = new SeedlinkNetwork("EarthScope comparison " + i, "rtserve.earthscope.org", 18000);
            sources.add(source);
            db.getSeedlinkNetworks().add(source);
        }
        GlobalQuakeServer backend = new GlobalQuakeServer(new StationDatabaseManager(db));
        List<CountedStation> stations = new ArrayList<>();
        for (JsonElement element : spec.getAsJsonArray("entries")) {
            SeedlinkNetwork source = sources.get(stations.size() % sources.size());
            CountedStation station = new CountedStation(element.getAsJsonObject(), stations.size(), source);
            stations.add(station);
            backend.getStationManager().getStations().add(station);
            source.selectedStations++;
        }
        long started = System.currentTimeMillis();
        long runningAt = 0;
        String reason = "handshake-deadline";
        List<Map<String,Object>> history = new ArrayList<>();
        System.out.println(JSON.toJson(Map.of("startedAt", Instant.ofEpochMilli(started).toString(),
            "pid", ProcessHandle.current().pid(), "selected", stations.size(),
            "backend", backend.getClass().getName(), "reader", backend.getSeedlinkReader().getClass().getName())));
        backend.getSeedlinkReader().run();
        long nextReport = started;
        try {
            while (true) {
                long now = System.currentTimeMillis();
                if (sources.stream().allMatch(s -> s.status == SeedlinkStatus.RUNNING) && runningAt == 0) runningAt = now;
                if (now >= nextReport) {
                    long seen = stations.stream().filter(s -> s.received > 0).count();
                    long fresh = stations.stream().filter(s -> s.received > 0 && s.latestEnd <= now && now - s.latestEnd <= 180000).count();
                    Map<String,Object> row = new LinkedHashMap<>();
                    row.put("seconds", (now-started)/1000.0);
                    row.put("status", sources.stream().allMatch(s -> s.status == SeedlinkStatus.RUNNING) ? "RUNNING" : "CONNECTING");
                    row.put("ackStations", sources.stream().mapToInt(s -> s.connectedStations).sum());
                    row.put("sources", sources.stream().map(s -> Map.of(
                        "name", s.getName(), "status", s.status.toString(),
                        "selected", s.selectedStations, "ackStations", s.connectedStations)).toList());
                    row.put("records", records.get());
                    row.put("seen", seen);
                    row.put("fresh", fresh);
                    row.put("transferSeconds", runningAt == 0 ? null : (now-runningAt)/1000.0);
                    history.add(row);
                    System.out.println(JSON.toJson(row));
                    nextReport = now + 15000;
                }
                if (sources.stream().anyMatch(s -> s.status == SeedlinkStatus.DISCONNECTED) && now-started > 5000) { reason = "backend-disconnected"; break; }
                if (runningAt != 0 && now-runningAt >= Long.parseLong(args[2])*1000) { reason = "transfer-deadline"; break; }
                if (runningAt == 0 && now-started >= Long.parseLong(args[3])*1000) break;
                if (Files.exists(directory.resolve("stop"))) { reason = "requested-stop"; break; }
                Thread.sleep(200);
            }
        } finally {
            backend.getSeedlinkReader().stop();
            backend.destroy();
            Map<String,Object> result = new LinkedHashMap<>();
            result.put("reason", reason);
            result.put("startedAt", Instant.ofEpochMilli(started).toString());
            result.put("finishedAt", Instant.now().toString());
            result.put("selected", stations.size());
            result.put("connections", sources.size());
            result.put("history", history);
            result.put("records", records.get());
            result.put("seen", stations.stream().filter(s -> s.received > 0).count());
            Files.writeString(directory.resolve("result.json"), JSON.toJson(result));
            System.out.println(JSON.toJson(result));
        }
    }
}

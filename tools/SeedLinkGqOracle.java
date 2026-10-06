import java.nio.file.*;
import java.util.*;
import java.time.Instant;
import com.google.gson.*;
import globalquake.core.GlobalQuake;
import globalquake.core.Settings;
import globalquake.core.analysis.*;
import globalquake.core.station.AbstractStation;

// Runs upstream BetterAnalysis, not a second translation of the Dart algorithm.
// Input records are the untouched original MiniSEED decode audit JSON.
public class SeedLinkGqOracle {
    public static void main(String[] args) throws Exception {
        GlobalQuake.prepare(Path.of(args[1]).toAbsolutePath().getParent().toFile(), null);
        new GlobalQuake() {
            public boolean limitedWaveformBuffers() { return false; }
            public boolean limitedSettings() { return false; }
        };
        Settings.logsStoreTimeMinutes = 5;
        JsonArray records = JsonParser.parseString(Files.readString(Path.of(args[0])))
            .getAsJsonObject().getAsJsonArray("records");
        Map<String, AbstractStation> stations = new HashMap<>();
        Map<String, Long> seconds = new HashMap<>();
        Map<String, Long> ends = new HashMap<>();
        JsonArray output = new JsonArray();
        for (JsonElement element : records) {
            JsonObject record = element.getAsJsonObject();
            String id = record.get("id").getAsString();
            double rate = record.get("sampleRate").getAsDouble();
            long start = Instant.parse(record.get("start").getAsString()).toEpochMilli();
            AbstractStation station = stations.computeIfAbsent(id, key ->
                new AbstractStation("TC", "QUEP", key.substring(key.length()-3),
                    "", 0, 0, 0, stations.size(), null, 3e8) {
                    public gqserver.api.packets.station.InputType getInputType() {
                        return gqserver.api.packets.station.InputType.VELOCITY;
                    }
                });
            BetterAnalysis analysis = (BetterAnalysis) station.getAnalysis();
            if (analysis.getSampleRate() != rate) {
                analysis.setSampleRate(rate);
                analysis.reset();
            }
            if (ends.containsKey(id) && start - ends.get(id) > 1000) {
                analysis.reset(); station.reset(); seconds.remove(id);
            }
            if (analysis.getStatus() != AnalysisStatus.INIT) analysis.numRecords++;
            JsonArray samples = record.getAsJsonArray("samples");
            long last = start;
            for (int i = 0; i < samples.size(); i++) {
                last = start + (long)(i * 1000.0 / rate);
                long second = last / 1000;
                if (seconds.containsKey(id) && seconds.get(id) != second) {
                    station.second(last);
                }
                seconds.put(id, second);
                analysis.nextSample(samples.get(i).getAsInt(), last, last);
            }
            ends.put(id, last);
            JsonObject row = new JsonObject();
            row.addProperty("offset", record.get("offset").getAsInt());
            row.addProperty("id", id);
            if (analysis.getStatus() != AnalysisStatus.INIT && analysis.numRecords >= 3)
                row.addProperty("ratio", station.getMaxRatio60S());
            row.addProperty("event", analysis.getStatus() == AnalysisStatus.EVENT && analysis.numRecords >= 3);
            output.add(row);
        }
        Files.writeString(Path.of(args[1]), new GsonBuilder().setPrettyPrinting().create().toJson(output));
        System.out.println("Oracle records: " + output.size());
        System.exit(0); // The upstream Settings watcher is not a test worker.
    }
}

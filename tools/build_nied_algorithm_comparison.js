'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const ALGORITHM_IDS = {
  production: 'production_nied_dart_hyp',
  kanameishi: 'kanameishi_original_js',
  srev: 'srev_kaizou_scratch',
};

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (!key.startsWith('--')) throw new Error(`Unexpected argument: ${key}`);
    const value = argv[index + 1];
    if (value == null || value.startsWith('--')) throw new Error(`Missing value for ${key}`);
    result[key.slice(2)] = value;
    index += 1;
  }
  return result;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function sha256Buffer(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex').toUpperCase();
}

function sha256File(filePath) {
  return sha256Buffer(fs.readFileSync(filePath));
}

function finiteNumber(value) {
  if (value == null || value === '' || typeof value === 'boolean') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function list(value) {
  return Array.isArray(value) ? value : [];
}

function map(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function normalizedIds(value) {
  return [...new Set(list(value)
    .filter((item) => item != null && item !== '')
    .map(String))]
    .sort((left, right) => left.localeCompare(right, 'en'));
}

function percentile(values, probability) {
  const sorted = values.filter(Number.isFinite).sort((left, right) => left - right);
  if (sorted.length === 0) return null;
  const position = (sorted.length - 1) * probability;
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  if (lower === upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
}

function distribution(values) {
  const finite = values.filter(Number.isFinite);
  return {
    count: finite.length,
    median: percentile(finite, 0.5),
    p90: percentile(finite, 0.9),
    max: finite.length === 0 ? null : Math.max(...finite),
    final: finite.length === 0 ? null : finite[finite.length - 1],
  };
}

function parseTime(value, assumeJst = false) {
  if (typeof value !== 'string' || value.length === 0) return null;
  const hasZone = /(?:Z|[+-]\d\d:\d\d)$/.test(value);
  const millis = Date.parse(hasZone || !assumeJst ? value : `${value}+09:00`);
  return Number.isFinite(millis) ? millis : null;
}

function haversineKm(left, right) {
  if (!left || !right) return null;
  const lat1 = finiteNumber(left.latitude);
  const lng1 = finiteNumber(left.longitude);
  const lat2 = finiteNumber(right.latitude);
  const lng2 = finiteNumber(right.longitude);
  if ([lat1, lng1, lat2, lng2].some((value) => value == null)) return null;
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(lat2 - lat1);
  const dLng = radians(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dLng / 2) ** 2;
  return 6371.0088 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function productionSource(estimate) {
  if (!estimate) return null;
  const diagnostics = map(estimate.diagnostics);
  const waveCounts = map(diagnostics.wave_counts);
  const selectedDetectionId = finiteNumber(diagnostics.selected_detection_id);
  const selectedDetection = list(diagnostics.detection_ids).find(
    (item) => finiteNumber(map(item).id) === selectedDetectionId
  );
  const selectedDetectionStationIds = normalizedIds(
    map(selectedDetection).assigned_station_codes
  );
  const memberStationIds = selectedDetectionStationIds.length > 0
    ? selectedDetectionStationIds
    : normalizedIds(Object.keys(map(diagnostics.station_assignment_accepted)));
  const effectiveStationCount = finiteNumber(diagnostics.effective_station_count) ??
    finiteNumber(estimate.supportingStationCount);
  const weightSum = finiteNumber(diagnostics.weight_sum);
  const score = finiteNumber(diagnostics.score);
  const errorLevel = finiteNumber(diagnostics.error_level);
  const valid = finiteNumber(estimate.latitude) != null &&
    finiteNumber(estimate.longitude) != null &&
    effectiveStationCount > 0 &&
    weightSum > 0 &&
    score != null &&
    errorLevel != null;
  return {
    sourceId: selectedDetectionId,
    valid,
    rejectionReason: valid ? null : 'missing_finite_source_support_or_positive_weight',
    latitude: finiteNumber(estimate.latitude),
    longitude: finiteNumber(estimate.longitude),
    depthKm: finiteNumber(estimate.depthKm),
    originTimeEpochMs: parseTime(estimate.originTime),
    score,
    errorLevel,
    rmseSeconds: finiteNumber(diagnostics.rmse),
    effectiveStationCount,
    weightSum,
    waveCounts: {
      P: finiteNumber(waveCounts.P) ?? 0,
      S: finiteNumber(waveCounts.S) ?? 0,
      O: finiteNumber(waveCounts.O) ?? 0,
      L: 0,
    },
    memberStationIds,
    qualityScore: finiteNumber(diagnostics.quality_score),
    qualityRank: diagnostics.quality_rank ?? null,
    searchStage: diagnostics.search_schedule_reference ?? diagnostics.search_schedule ?? null,
    searchIterationCount: finiteNumber(diagnostics.search_iteration_count),
    candidateEvaluationCount: finiteNumber(diagnostics.search_candidate_score_call_count),
    rejectedCandidateCount: finiteNumber(map(diagnostics.searched_result).rejected_candidate_count),
    method: estimate.method ?? null,
  };
}

function canonicalProduction(report) {
  const inputCase = list(report.cases)[0];
  if (!inputCase) throw new Error('Production report contains no cases');
  return list(inputCase.frames).map((frame, frameIndex) => {
    const source = productionSource(frame.estimate);
    return {
      frameIndex,
      observedAt: frame.observedAtJst ?? null,
      observedAtEpochMs: parseTime(frame.observedAtJst, true),
      runtimeMicros: finiteNumber(frame.algorithmRuntimeMicros),
      sources: source ? [source] : [],
      rejectionReason: source?.valid ? null : 'no_finite_supported_result',
      inputStationCount: finiteNumber(map(frame.metadata).nied_hypocenter_input_diagnostics?.selected_active_count),
      memberCount: finiteNumber(frame.memberCount),
    };
  });
}

function canonicalKanameishi(report) {
  const inputCase = list(report.cases)[0];
  if (!inputCase) throw new Error('Kanameishi report contains no cases');
  return list(inputCase.frames).map((frame, frameIndex) => ({
    frameIndex,
    observedAt: frame.observedAt ?? null,
    observedAtEpochMs: parseTime(frame.observedAt, true),
    runtimeMicros: finiteNumber(frame.runtimeMicros),
    sources: list(frame.sources).map((source) => ({
      ...source,
      memberStationIds: normalizedIds(
        list(source.stations).map((station) => station.stationId)
      ),
    })),
    rejectionReason: frame.rejectionReason ?? null,
    inputStationCount: finiteNumber(map(frame.input).activeStationCount),
    searchInvocationCount: finiteNumber(frame.searchInvocationCount),
    candidateEvaluationCount: finiteNumber(frame.candidateEvaluationCount),
    rejectedCandidateCount: finiteNumber(frame.rejectedCandidateCount),
  }));
}

function canonicalSrev(report) {
  return list(report.frames).map((frame, frameIndex) => ({
    frameIndex,
    observedAt: frame.observedAtUtc ?? null,
    observedAtEpochMs: parseTime(frame.observedAtUtc),
    runtimeMicros: finiteNumber(frame.runtimeMicros),
    sources: list(frame.sources).map((source) => ({
      ...source,
      sourceId: source.detectionId ?? null,
      originTimeEpochMs: finiteNumber(source.originTimeEpochMs),
      waveCounts: map(source.waveCounts),
      memberStationIds: normalizedIds(
        list(source.stations).map((station) => station.stationCode)
      ),
    })),
    rejectionReason: list(frame.sources).some((source) => source.valid)
      ? null
      : 'no_finite_supported_result',
    inputStationCount: finiteNumber(frame.inputStationCount),
    candidateEvaluationCount: null,
    rejectedCandidateCount: null,
  }));
}

function primarySource(sources) {
  const valid = sources.filter((source) => source?.valid === true);
  if (valid.length === 0) return null;
  return [...valid].sort((left, right) => {
    const stationDelta = (finiteNumber(right.effectiveStationCount) ?? -1) -
      (finiteNumber(left.effectiveStationCount) ?? -1);
    if (stationDelta !== 0) return stationDelta;
    const scoreDelta = (finiteNumber(left.score) ?? Number.POSITIVE_INFINITY) -
      (finiteNumber(right.score) ?? Number.POSITIVE_INFINITY);
    if (scoreDelta !== 0) return scoreDelta;
    return String(left.sourceId ?? '').localeCompare(String(right.sourceId ?? ''), 'en');
  })[0];
}

function waveCounts(source) {
  const raw = map(source?.waveCounts);
  return {
    P: finiteNumber(raw.P) ?? finiteNumber(source?.pStationCount) ?? 0,
    S: finiteNumber(raw.S) ?? finiteNumber(source?.sStationCount) ?? 0,
    O: finiteNumber(raw.O) ?? 0,
    L: finiteNumber(raw.L) ?? 0,
  };
}

function summarizeAlgorithm(id, label, frames, truth) {
  const truthPoint = {latitude: truth.latitude, longitude: truth.longitude};
  const evaluatedFrames = [];
  const rejectionReasons = {};
  let previous = null;
  let previousWaves = null;
  let phaseCountChangedFrames = 0;
  let previousMembership = null;
  let membershipChangedFrames = 0;
  let membershipComparedFrames = 0;
  let membershipCoverageFrames = 0;
  const jumps = [];
  const horizontalErrors = [];
  const depthErrors = [];
  const originTimeErrors = [];
  const effectiveCounts = [];
  const weightSums = [];
  const pCounts = [];
  const sCounts = [];
  const oCounts = [];
  const lCounts = [];
  for (const frame of frames) {
    const primary = primarySource(frame.sources);
    if (!primary) {
      const reason = frame.rejectionReason || 'no_valid_primary_source';
      rejectionReasons[reason] = (rejectionReasons[reason] || 0) + 1;
      evaluatedFrames.push({
        frameIndex: frame.frameIndex,
        observedAt: frame.observedAt,
        observedAtEpochMs: frame.observedAtEpochMs,
        runtimeMicros: frame.runtimeMicros,
        sourceCount: frame.sources.length,
        rejectionReason: reason,
        primary: null,
      });
      continue;
    }
    const horizontalErrorKm = haversineKm(primary, truthPoint);
    const depthErrorKm = finiteNumber(primary.depthKm) == null || truth.depthKm == null
      ? null
      : Math.abs(primary.depthKm - truth.depthKm);
    const originTimeErrorSeconds = finiteNumber(primary.originTimeEpochMs) == null ||
      truth.originTimeEpochMs == null
      ? null
      : Math.abs(primary.originTimeEpochMs - truth.originTimeEpochMs) / 1000;
    const jumpKm = previous == null ? null : haversineKm(previous, primary);
    if (horizontalErrorKm != null) horizontalErrors.push(horizontalErrorKm);
    if (depthErrorKm != null) depthErrors.push(depthErrorKm);
    if (originTimeErrorSeconds != null) originTimeErrors.push(originTimeErrorSeconds);
    if (jumpKm != null) jumps.push(jumpKm);
    const counts = waveCounts(primary);
    const countSignature = JSON.stringify(counts);
    if (previousWaves != null && countSignature !== previousWaves) phaseCountChangedFrames += 1;
    previousWaves = countSignature;
    const memberStationIds = normalizedIds(primary.memberStationIds);
    if (memberStationIds.length > 0) {
      membershipCoverageFrames += 1;
      const membershipSignature = JSON.stringify(memberStationIds);
      if (previousMembership != null) {
        membershipComparedFrames += 1;
        if (membershipSignature !== previousMembership) membershipChangedFrames += 1;
      }
      previousMembership = membershipSignature;
    }
    const effective = finiteNumber(primary.effectiveStationCount);
    const weight = finiteNumber(primary.weightSum);
    if (effective != null) effectiveCounts.push(effective);
    if (weight != null) weightSums.push(weight);
    pCounts.push(counts.P);
    sCounts.push(counts.S);
    oCounts.push(counts.O);
    lCounts.push(counts.L);
    evaluatedFrames.push({
      frameIndex: frame.frameIndex,
      observedAt: frame.observedAt,
      observedAtEpochMs: frame.observedAtEpochMs,
      runtimeMicros: frame.runtimeMicros,
      sourceCount: frame.sources.length,
      rejectionReason: null,
      primary: {
        sourceId: primary.sourceId ?? primary.detectionId ?? null,
        latitude: primary.latitude,
        longitude: primary.longitude,
        depthKm: primary.depthKm,
        originTimeEpochMs: primary.originTimeEpochMs,
        horizontalErrorKm,
        depthErrorKm,
        originTimeErrorSeconds,
        jumpKm,
        effectiveStationCount: effective,
        weightSum: weight,
        waveCounts: counts,
        memberStationCount: memberStationIds.length,
        memberStationIds,
        score: finiteNumber(primary.score),
        errorLevel: finiteNumber(primary.errorLevel),
        rmseSeconds: finiteNumber(primary.rmseSeconds),
        qualityRank: primary.qualityRank ?? null,
        searchStage: primary.searchStage ?? null,
        searchIterationCount: finiteNumber(primary.searchIterationCount),
        candidateEvaluationCount:
          finiteNumber(primary.candidateEvaluationCount) ?? finiteNumber(frame.candidateEvaluationCount),
        rejectedCandidateCount:
          finiteNumber(primary.rejectedCandidateCount) ?? finiteNumber(frame.rejectedCandidateCount),
      },
    });
    previous = primary;
  }
  const validFrames = evaluatedFrames.filter((frame) => frame.primary != null);
  const first = validFrames[0] ?? null;
  const final = validFrames[validFrames.length - 1] ?? null;
  const candidateCounts = validFrames
    .map((frame) => finiteNumber(frame.primary.candidateEvaluationCount))
    .filter((value) => value != null);
  const rejectedCounts = validFrames
    .map((frame) => finiteNumber(frame.primary.rejectedCandidateCount))
    .filter((value) => value != null);
  const searchIterations = validFrames
    .map((frame) => finiteNumber(frame.primary.searchIterationCount))
    .filter((value) => value != null);
  return {
    id,
    label,
    selectionPolicy:
      'valid source with greatest effectiveStationCount, then lowest algorithm score, then source id',
    frameCoverage: {
      inputFrameCount: frames.length,
      validResultFrameCount: validFrames.length,
      rejectedOrNoResultFrameCount: frames.length - validFrames.length,
      totalSourceOutputCount: frames.reduce((sum, frame) => sum + frame.sources.length, 0),
    },
    firstResult: first == null ? null : {
      ...first.primary,
      frameIndex: first.frameIndex,
      observedAt: first.observedAt,
      latencyFromTruthOriginSeconds: truth.originTimeEpochMs == null ||
        first.observedAtEpochMs == null
        ? null
        : (first.observedAtEpochMs - truth.originTimeEpochMs) / 1000,
    },
    finalResult: final == null ? null : {
      ...final.primary,
      frameIndex: final.frameIndex,
      observedAt: final.observedAt,
    },
    accuracy: {
      horizontalErrorKm: distribution(horizontalErrors),
      absoluteDepthErrorKm: distribution(depthErrors),
      absoluteOriginTimeErrorSeconds: distribution(originTimeErrors),
    },
    stability: {
      interFrameJumpKm: distribution(jumps),
      phaseCountChangedFrameCount: phaseCountChangedFrames,
      phaseCountComparedFrameCount: Math.max(0, validFrames.length - 1),
      membershipChangedFrameCount: membershipChangedFrames,
      membershipComparedFrameCount: membershipComparedFrames,
      membershipCoverageFrameCount: membershipCoverageFrames,
      memberCountChangedFrameCount: phaseCountChangedFrames,
      memberCountComparedFrameCount: Math.max(0, validFrames.length - 1),
    },
    support: {
      effectiveStationCount: distribution(effectiveCounts),
      weightSum: distribution(weightSums),
      weightCoverageFrameCount: weightSums.length,
      pStationCount: distribution(pCounts),
      sStationCount: distribution(sCounts),
      oStationCount: distribution(oCounts),
      lStationCount: distribution(lCounts),
    },
    search: {
      runtimeMicros: distribution(frames.map((frame) => finiteNumber(frame.runtimeMicros))),
      candidateEvaluationCount: distribution(candidateCounts),
      rejectedCandidateCount: distribution(rejectedCounts),
      searchIterationCount: distribution(searchIterations),
    },
    rejectionReasons,
    frames: evaluatedFrames,
  };
}

function inputIntegrity(captureDirectory, manifest) {
  const records = list(manifest.records);
  const manifestByFile = new Map(
    records.filter((record) => record?.file).map((record) => [record.file, record])
  );
  const files = fs.readdirSync(captureDirectory)
    .filter((name) => /\.gif$/i.test(name))
    .sort((left, right) => left.localeCompare(right, 'en'))
    .map((name) => {
      const filePath = path.join(captureDirectory, name);
      const stat = fs.statSync(filePath);
      const hash = sha256File(filePath);
      const expected = manifestByFile.get(name);
      return {
        name,
        bytes: stat.size,
        sha256: hash,
        manifestBytesMatch: expected == null ? null : Number(expected.bytes) === stat.size,
        manifestSha256Match: expected == null
          ? null
          : String(expected.sha256).toUpperCase() === hash,
      };
    });
  const digestInput = files
    .map((file) => `${file.name}\0${file.bytes}\0${file.sha256}\n`)
    .join('');
  return {
    captureDirectory: path.resolve(captureDirectory),
    rawGifCount: files.length,
    totalBytes: files.reduce((sum, file) => sum + file.bytes, 0),
    aggregateSha256: sha256Buffer(Buffer.from(digestInput, 'utf8')),
    manifestRecordCount: records.length,
    byteMismatchCount: files.filter((file) => file.manifestBytesMatch === false).length,
    sha256MismatchCount: files.filter((file) => file.manifestSha256Match === false).length,
    rawInputUnmodified: true,
    files,
  };
}

function frameSetAudit(algorithms) {
  const sets = Object.fromEntries(
    Object.entries(algorithms).map(([id, frames]) => [
      id,
      new Set(frames.map((frame) => frame.observedAtEpochMs).filter((value) => value != null)),
    ])
  );
  const union = new Set(Object.values(sets).flatMap((set) => [...set]));
  const missingByAlgorithm = {};
  for (const [id, set] of Object.entries(sets)) {
    missingByAlgorithm[id] = [...union].filter((value) => !set.has(value)).sort();
  }
  return {
    sameFrameSet: Object.values(missingByAlgorithm).every((values) => values.length === 0),
    unionFrameCount: union.size,
    frameCountByAlgorithm: Object.fromEntries(
      Object.entries(sets).map(([id, set]) => [id, set.size])
    ),
    missingEpochMsByAlgorithm: missingByAlgorithm,
  };
}

function compatibilitySummary(report, srevReport) {
  if (!report) return null;
  const rows = list(map(report.result).procedures);
  const different = rows.filter((row) => row.status === 'different').map((row) => row.proccode);
  const overrides = new Set(list(map(srevReport.provenance).overriddenProcedures));
  return {
    srevProjectSha256: map(report.srev).projectSha256 ?? null,
    compiledBaselineProjectSha256: map(report.comparison).projectSha256 ?? null,
    identicalProcedureCount: finiteNumber(map(report.result).identicalCount),
    differentProcedureCount: finiteNumber(map(report.result).differentCount),
    differentProcedures: different,
    overriddenProcedures: [...overrides],
    uncoveredDifferentProcedures: different.filter((name) => !overrides.has(name)),
    verified: different.every((name) => overrides.has(name)),
  };
}

function markdown(report) {
  const number = (value, digits = 2) =>
    Number.isFinite(value) ? value.toFixed(digits) : '-';
  const accuracyRows = Object.values(report.algorithms).map((algorithm) => {
    const accuracy = algorithm.accuracy.horizontalErrorKm;
    const depth = algorithm.accuracy.absoluteDepthErrorKm;
    const origin = algorithm.accuracy.absoluteOriginTimeErrorSeconds;
    const jump = algorithm.stability.interFrameJumpKm;
    return `| ${algorithm.label} | ${algorithm.frameCoverage.validResultFrameCount}/` +
      `${algorithm.frameCoverage.inputFrameCount} | ` +
      `${number(algorithm.firstResult?.latencyFromTruthOriginSeconds)} | ` +
      `${number(algorithm.firstResult?.horizontalErrorKm)} | ${number(accuracy.median)} | ` +
      `${number(accuracy.p90)} | ${number(accuracy.final)} | ${number(depth.p90)} | ` +
      `${number(depth.final)} | ${number(origin.p90)} | ${number(origin.final)} | ` +
      `${number(jump.p90)} | ${number(jump.max)} |`;
  });
  const factorRows = Object.values(report.algorithms).map((algorithm) => {
    const support = algorithm.support;
    const search = algorithm.search;
    return `| ${algorithm.label} | ${number(support.effectiveStationCount.final, 0)} | ` +
      `${number(support.pStationCount.final, 0)} | ${number(support.sStationCount.final, 0)} | ` +
      `${number(support.oStationCount.final, 0)} | ${number(support.lStationCount.final, 0)} | ` +
      `${number(support.weightSum.final, 4)} | ${support.weightCoverageFrameCount}/` +
      `${algorithm.frameCoverage.validResultFrameCount} | ` +
      `${algorithm.stability.phaseCountChangedFrameCount}/` +
      `${algorithm.stability.phaseCountComparedFrameCount} | ` +
      `${algorithm.stability.membershipChangedFrameCount}/` +
      `${algorithm.stability.membershipComparedFrameCount} | ` +
      `${number(search.candidateEvaluationCount.p90, 0)} | ` +
      `${number(search.rejectedCandidateCount.p90, 0)} | ` +
      `${number(search.runtimeMicros.p90 == null ? null : search.runtimeMicros.p90 / 1000)} |`;
  });
  const rejectionRows = Object.values(report.algorithms).map((algorithm) =>
    `| ${algorithm.label} | ${algorithm.frameCoverage.rejectedOrNoResultFrameCount} | ` +
    `${Object.entries(algorithm.rejectionReasons)
      .map(([reason, count]) => `${reason}: ${count}`)
      .join('; ') || '-'} |`
  );
  const srevRandom = map(map(report.provenance).srev).random;
  const srevSummary = map(map(report.algorithms).srev_kaizou_scratch);
  return [
    '# NIED 三算法震源推算诊断',
    '',
    `事件：${report.truth.region || report.caseId}`,
    '',
    `固定真值：${report.truth.source}；${report.truth.latitude}, ${report.truth.longitude}；` +
      `深度 ${report.truth.depthKm} km；起震 ${report.truth.originTime}。`,
    '',
    `同帧校验：${report.sameFrameAudit.sameFrameSet ? '通过' : '未通过'}；原始 GIF ${report.inputIntegrity.rawGifCount} 张；SHA-256 不一致 ${report.inputIntegrity.sha256MismatchCount}。`,
    '',
    '## 精度与稳定性',
    '',
    '| 算法 | 有效帧 | 首次延迟 s | 首次水平 km | 水平中位 km | 水平 P90 km | 最终水平 km | 深度误差 P90 km | 最终深度误差 km | 起震误差 P90 s | 最终起震误差 s | 跳变 P90 km | 最大跳变 km |',
    '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
    ...accuracyRows,
    '',
    '## 测站与搜索因素',
    '',
    '| 算法 | 最终有效站 | P | S | O | L | 最终权重和 | 权重覆盖帧 | P/S/O/L 计数变化帧 | 测站成员变化帧 | 候选 P90 | 拒绝候选 P90 | 耗时 P90 ms |',
    '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
    ...factorRows,
    '',
    '## 无结果与拒绝',
    '',
    '| 算法 | 无有效结果帧 | 原因 |',
    '|---|---:|---|',
    ...rejectionRows,
    '',
    '## 可复现性与来源',
    '',
    `- srev 随机算法：${srevRandom?.generator ?? '-'}；种子：` +
      `${srevRandom?.seed ?? '-'}；抽样次数：${srevRandom?.drawCount ?? '-'}。`,
    `- srev 科学轨迹 SHA-256：` +
      `${map(report.srevDeterminism).deterministicTrajectorySha256 ?? '-'}`,
    `- srev 有效结果帧：${srevSummary.frameCoverage?.validResultFrameCount ?? '-'}；` +
      `Scratch 未暴露的权重和候选评估次数保持 null。`,
    `- srev 结构核验：${report.srevCompiledCoreCompatibility?.verified ? '通过' : '未通过或缺失'}；` +
      `未覆盖差异 ${list(report.srevCompiledCoreCompatibility?.uncoveredDifferentProcedures).length}。`,
    `- 参考项目算法源 SHA-256：${map(report.provenance.kanameishi).algorithmSourceSha256 ?? '-'}`,
    '',
    '说明：统一表中的主震源只用于可比统计；各算法的全部原始输出保留在各自 raw report 中。',
    'srev Scratch 不暴露权重和候选评估次数时保持 null，不以推测值补齐。',
    '',
  ].join('\n');
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  for (const required of ['manifest', 'capture', 'production', 'kanameishi', 'srev', 'output-dir']) {
    if (!args[required]) throw new Error(`Missing required --${required}`);
  }
  const manifestPath = path.resolve(args.manifest);
  const captureDirectory = path.resolve(args.capture);
  const productionPath = path.resolve(args.production);
  const kanameishiPath = path.resolve(args.kanameishi);
  const srevPath = path.resolve(args.srev);
  const outputDirectory = path.resolve(args['output-dir']);
  const manifest = readJson(manifestPath);
  const productionReport = readJson(productionPath);
  const kanameishiReport = readJson(kanameishiPath);
  const srevReport = readJson(srevPath);
  const compatibility = args.compatibility ? readJson(path.resolve(args.compatibility)) : null;
  const event = map(manifest.event);
  const truth = {
    source: event.truthSource ?? 'capture_manifest.event',
    region: event.region ?? null,
    latitude: finiteNumber(event.latitude),
    longitude: finiteNumber(event.longitude),
    depthKm: finiteNumber(event.depthKm),
    magnitude: finiteNumber(event.magnitude),
    originTime: event.originTimeJst ?? event.originTimeInput ?? null,
    originTimeEpochMs: parseTime(event.originTimeJst ?? event.originTimeInput),
  };
  if (truth.latitude == null || truth.longitude == null) {
    throw new Error('Manifest event truth latitude/longitude is required');
  }
  const canonical = {
    [ALGORITHM_IDS.production]: canonicalProduction(productionReport),
    [ALGORITHM_IDS.kanameishi]: canonicalKanameishi(kanameishiReport),
    [ALGORITHM_IDS.srev]: canonicalSrev(srevReport),
  };
  const integrity = inputIntegrity(captureDirectory, manifest);
  const report = {
    schemaVersion: 1,
    generatedAtUtc: new Date().toISOString(),
    diagnosticOnly: true,
    writesProductionState: false,
    caseId: manifest.caseId ?? path.basename(captureDirectory),
    truth,
    experimentRules: {
      rawGifBytesModified: false,
      sameDecodedFrameSource: true,
      fixedTruthForAllAlgorithms: true,
      productionWritebackDisabled: true,
      missingMetricsRemainNull: true,
    },
    inputIntegrity: integrity,
    sameFrameAudit: frameSetAudit(canonical),
    srevCompiledCoreCompatibility: compatibilitySummary(compatibility, srevReport),
    srevDeterminism: {
      random: map(srevReport.provenance).random ?? null,
      deterministicTrajectorySha256:
        map(srevReport.summary).deterministicTrajectorySha256 ?? null,
    },
    rawReports: {
      production: {path: productionPath, sha256: sha256File(productionPath)},
      kanameishi: {path: kanameishiPath, sha256: sha256File(kanameishiPath)},
      srev: {path: srevPath, sha256: sha256File(srevPath)},
    },
    provenance: {
      production: {
        method: 'NiedDartHypSourceEstimator',
        searchSchedule: 'referenceBroadFourStage',
        writebackPolicy: 'nonIncreasingCurrent',
      },
      kanameishi: kanameishiReport.provenance,
      srev: srevReport.provenance,
    },
    algorithms: {
      [ALGORITHM_IDS.production]: summarizeAlgorithm(
        ALGORITHM_IDS.production,
        '当前生产 NiedDartHypSourceEstimator',
        canonical[ALGORITHM_IDS.production],
        truth
      ),
      [ALGORITHM_IDS.kanameishi]: summarizeAlgorithm(
        ALGORITHM_IDS.kanameishi,
        '参考项目 kanameishi-dev 原始 JS',
        canonical[ALGORITHM_IDS.kanameishi],
        truth
      ),
      [ALGORITHM_IDS.srev]: summarizeAlgorithm(
        ALGORITHM_IDS.srev,
        't0729/srev-kaizou Scratch',
        canonical[ALGORITHM_IDS.srev],
        truth
      ),
    },
  };
  fs.mkdirSync(outputDirectory, {recursive: true});
  const reportPath = path.join(outputDirectory, 'comparison_report.json');
  const markdownPath = path.join(outputDirectory, 'comparison_report.md');
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  fs.writeFileSync(markdownPath, markdown(report), 'utf8');
  process.stdout.write(`${JSON.stringify({
    report: reportPath,
    markdown: markdownPath,
    sameFrameSet: report.sameFrameAudit.sameFrameSet,
    rawGifCount: integrity.rawGifCount,
    sha256MismatchCount: integrity.sha256MismatchCount,
  }, null, 2)}\n`);
}

module.exports = {
  canonicalKanameishi,
  canonicalProduction,
  canonicalSrev,
  frameSetAudit,
  summarizeAlgorithm,
};

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.stack || error}\n`);
    process.exitCode = 1;
  }
}

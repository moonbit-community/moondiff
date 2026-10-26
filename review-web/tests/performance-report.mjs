import { writeFile } from 'node:fs/promises';

export function summarizeSamples(samples) {
  if (!samples.length || samples.some(value => !Number.isFinite(value))) {
    throw new Error(`Performance samples must be nonempty finite measurements: ${JSON.stringify(samples)}`);
  }
  const sorted = [...samples].sort((a, b) => a - b);
  const percentile = p => {
    const index = (sorted.length - 1) * p, low = Math.floor(index);
    return sorted[low] + (sorted[Math.ceil(index)] - sorted[low]) * (index - low);
  };
  return { count: samples.length, p50: percentile(.5), p95: percentile(.95) };
}

export async function writePerformanceReport(info, name, { fixture, cpuRate, samples, groups, ...details }) {
  if (!fixture || !cpuRate) throw new Error('Performance reports require fixture and CPU information');
  const report = { schemaVersion: 1, fixture, cpuRate, ...details, samples,
    summary: Object.fromEntries(Object.entries(groups).map(([label, values]) => [label, summarizeSamples(values)])),
  };
  const path = info.outputPath(name);
  await writeFile(path, JSON.stringify(report, null, 2));
  await info.attach(name, { contentType: 'application/json', path });
  return report;
}

export const comparisonOrder = [['A', 'B'], ['B', 'A']];

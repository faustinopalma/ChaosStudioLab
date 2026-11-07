import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';
import exec from 'k6/execution';
import { sha256 } from 'k6/crypto';

const apiBaseUrl = (__ENV.API_BASE_URL || '').replace(/\/+$/, '');
const apiToken = __ENV.API_TOKEN || '';
const runId = __ENV.RUN_ID || 'local';
const successfulOperationP95LimitMs = Number(__ENV.SUCCESS_P95_LIMIT_MS || 1000);
const successfulOperationDuration = new Trend('business_operation_duration', true);
const workloadAttemptSuccess = new Rate('workload_attempt_success');
const logicalOperationFailures = new Counter('logical_operation_failures');
const logicalOperationSuccesses = new Counter('logical_operation_successes');
const writeReconciliations = new Counter('write_reconciliations');
const writeUnknownOutcomes = new Counter('write_unknown_outcomes');
const canaryTickSuccess = new Rate('canary_tick_success');
const canaryTickDuration = new Trend('canary_tick_duration', true);

export const options = {
  scenarios: {
    workload: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 20),
      timeUnit: '1s',
      duration: __ENV.DURATION || '10m',
      preAllocatedVUs: Number(__ENV.PREALLOCATED_VUS || 50),
      maxVUs: Number(__ENV.MAX_VUS || 200),
      gracefulStop: '3m',
    },
    canary: {
      executor: 'constant-arrival-rate',
      rate: 1,
      timeUnit: '1s',
      duration: __ENV.DURATION || '10m',
      preAllocatedVUs: 2,
      maxVUs: 10,
      gracefulStop: '3m',
    },
  },
  thresholds: {
    business_operation_duration: [`p(95)<=${successfulOperationP95LimitMs}`],
  },
};

function emit(event) {
  console.log(`LAB_EVENT ${JSON.stringify({ runId, ...event })}`);
}

function headers() {
  return {
    Authorization: `Bearer ${apiToken}`,
    'Content-Type': 'application/json',
    'X-Run-Id': runId,
  };
}

function newGuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (character) => {
    const value = Math.floor(Math.random() * 16);
    return (character === 'x' ? value : ((value & 0x3) | 0x8)).toString(16);
  });
}

function checksum(payload) {
  return sha256(JSON.stringify(payload), 'hex');
}

function parseResponse(response) {
  if (!response.body) {
    return null;
  }
  try {
    return response.json();
  } catch {
    return null;
  }
}

function readOrder(operationId, expectedChecksum, phase, trackWorkload = true) {
  const startedAt = Date.now();
  const response = http.get(
    `${apiBaseUrl}/api/orders/${operationId}`,
    { headers: headers(), timeout: '8s', tags: { operation: 'read', phase } },
  );
  const elapsedMs = Date.now() - startedAt;
  const body = parseResponse(response);
  const valid = check(response, {
    'read returns 200': (result) => result.status === 200,
    'read returns requested operation': () => body && body.operationId === operationId,
    'read checksum matches': () => body && body.payloadSha256 === expectedChecksum,
  });

  if (trackWorkload) {
    workloadAttemptSuccess.add(response.status === 200 && valid ? 1 : 0);
    if (response.status < 200 || response.status >= 300 || !valid) {
      logicalOperationFailures.add(1, { operation: 'read' });
    } else {
      successfulOperationDuration.add(elapsedMs, { operation: 'read' });
      logicalOperationSuccesses.add(1, { operation: 'read' });
    }
  }

  emit({
    type: 'attempt',
    phase,
    operation: 'read',
    operationId,
    attempt: 1,
    recordedAtUtc: new Date().toISOString(),
    status: response.status,
    httpProtocol: response.proto || null,
    transportError: response.error || null,
    transportErrorCode: response.error_code || 0,
    durationMs: elapsedMs,
    expectedChecksum,
    responseChecksum: body && body.payloadSha256,
    errorCode: body && body.error,
    instanceId: response.headers['X-Lab-Instance-Id'] || null,
    processId: response.headers['X-Lab-Process-Id'] || null,
    processStartedAtUtc: response.headers['X-Lab-Process-Start-Utc'] || null,
    success: response.status === 200 && valid,
    parseError: Boolean(response.body && !body),
  });
  const succeeded = response.status === 200 && valid;
  if (trackWorkload) {
    emit({
      type: 'businessOperation',
      phase,
      operation: 'read',
      operationId,
      startedAtUtc: new Date(startedAt).toISOString(),
      completedAtUtc: new Date().toISOString(),
      durationMs: elapsedMs,
      success: succeeded,
      outcome: succeeded ? 'completed' : 'failed',
    });
  }
  return succeeded;
}

function reconcileOrder(operationId, expectedChecksum, phase) {
  const startedAt = Date.now();
  const response = http.get(
    `${apiBaseUrl}/api/orders/${operationId}`,
    { headers: headers(), timeout: '8s', tags: { operation: 'reconciliation', phase } },
  );
  const elapsedMs = Date.now() - startedAt;
  const body = parseResponse(response);
  let outcome = 'unknown';

  if (response.status === 404) {
    outcome = 'absent';
  } else if (
    response.status === 200
    && body
    && body.operationId === operationId
    && body.payloadSha256 === expectedChecksum
  ) {
    outcome = 'committed';
  } else if (response.status === 200) {
    outcome = 'conflict';
  }

  emit({
    type: 'reconciliation',
    phase,
    operationId,
    recordedAtUtc: new Date().toISOString(),
    status: response.status,
    httpProtocol: response.proto || null,
    transportError: response.error || null,
    transportErrorCode: response.error_code || 0,
    durationMs: elapsedMs,
    expectedChecksum,
    responseChecksum: body && body.payloadSha256,
    outcome,
    parseError: Boolean(response.body && !body),
  });
  return outcome;
}

function writeOrder(operationId, payload, phase, trackWorkload = true) {
  const expectedChecksum = checksum(payload);
  const body = JSON.stringify({ operationId, payload });
  const operationStartedAt = Date.now();
  const deadline = operationStartedAt + 180000;
  let attempt = 0;
  let outcome = 'unknown';

  while (Date.now() < deadline) {
    attempt += 1;
    const startedAt = Date.now();
    const response = http.post(
      `${apiBaseUrl}/api/orders`,
      body,
      { headers: headers(), timeout: '8s', tags: { operation: 'write', phase } },
    );
    const elapsedMs = Date.now() - startedAt;
    const responseBody = parseResponse(response);
    const responseChecksum = responseBody && responseBody.payloadSha256;
    const success = (response.status === 200 || response.status === 201)
      && responseBody
      && responseBody.operationId === operationId
      && responseChecksum === expectedChecksum;
    if (trackWorkload) {
      workloadAttemptSuccess.add(success ? 1 : 0);
    }

    emit({
      type: 'attempt',
      phase,
      operation: 'write',
      operationId,
      attempt,
      recordedAtUtc: new Date().toISOString(),
      status: response.status,
      durationMs: elapsedMs,
      expectedChecksum,
      responseChecksum,
      errorCode: responseBody && responseBody.error,
      instanceId: response.headers['X-Lab-Instance-Id'] || null,
      processId: response.headers['X-Lab-Process-Id'] || null,
      processStartedAtUtc: response.headers['X-Lab-Process-Start-Utc'] || null,
      success: Boolean(success),
      parseError: Boolean(response.body && !responseBody),
    });

    if (success) {
      outcome = reconcileOrder(
        operationId,
        expectedChecksum,
        `${phase}-write-reconciliation`,
      );
      if (outcome === 'committed' || outcome === 'absent' || outcome === 'conflict') {
        break;
      }
    }

    const retryable = response.status === 0 || response.status === 503;
    if ((!retryable && !success) || response.status === 409) {
      break;
    }

    const backoffMs = Math.min(250 * (2 ** Math.min(attempt - 1, 4)), 5000)
      + Math.floor(Math.random() * 1000);
    const remainingMs = deadline - Date.now();
    if (remainingMs <= 0) {
      break;
    }
    sleep(Math.min(backoffMs, remainingMs) / 1000);
  }

  if (outcome === 'unknown') {
    outcome = reconcileOrder(
      operationId,
      expectedChecksum,
      `${phase}-final-reconciliation`,
    );
  }

  const operationDurationMs = Date.now() - operationStartedAt;
  if (trackWorkload) {
    if (outcome === 'committed') {
      successfulOperationDuration.add(operationDurationMs, { operation: 'write' });
      logicalOperationSuccesses.add(1, { operation: 'write' });
    } else {
      logicalOperationFailures.add(1, { operation: `write-${outcome}` });
    }
  }
  if (outcome === 'committed' || outcome === 'absent') {
    if (trackWorkload) {
      writeReconciliations.add(1, { outcome });
    }
  } else if (trackWorkload) {
    writeUnknownOutcomes.add(1, { outcome });
  }
  if (trackWorkload) {
    emit({
      type: 'businessOperation',
      phase,
      operation: 'write',
      operationId,
      startedAtUtc: new Date(operationStartedAt).toISOString(),
      completedAtUtc: new Date().toISOString(),
      durationMs: operationDurationMs,
      success: outcome === 'committed',
      outcome,
    });
  }
  return outcome === 'committed';
}

export function setup() {
  if (!apiBaseUrl || !apiToken) {
    throw new Error('API_BASE_URL and API_TOKEN environment variables are required.');
  }

  const seedOrders = [];
  for (let index = 0; index < 5; index += 1) {
    const operationId = newGuid();
    const payload = {
      sku: `seed-${runId}-${index}`,
      quantity: index + 1,
      notes: 'synthetic load-test seed',
    };

    const expectedChecksum = checksum(payload);
    const startedAt = Date.now();
    const response = http.post(
      `${apiBaseUrl}/api/orders`,
      JSON.stringify({ operationId, payload }),
      { headers: headers(), timeout: '8s', tags: { operation: 'write', phase: 'setup' } },
    );
    const responseBody = parseResponse(response);
    const success = (response.status === 200 || response.status === 201)
      && responseBody
      && responseBody.operationId === operationId
      && responseBody.payloadSha256 === expectedChecksum;
    const outcome = success
      ? reconcileOrder(operationId, expectedChecksum, 'setup-reconciliation')
      : 'unknown';

    emit({
      type: 'attempt',
      phase: 'setup',
      operation: 'write',
      operationId,
      attempt: 1,
      recordedAtUtc: new Date().toISOString(),
      status: response.status,
      durationMs: Date.now() - startedAt,
      expectedChecksum,
      responseChecksum: responseBody && responseBody.payloadSha256,
      success: Boolean(success && outcome === 'committed'),
      parseError: Boolean(response.body && !responseBody),
    });

    if (!success || outcome !== 'committed') {
      throw new Error(`Unable to create and reconcile seed order ${operationId}.`);
    }
    seedOrders.push({ operationId, payloadSha256: expectedChecksum });
  }

  return { seedOrders };
}

export default function (data) {
  const iteration = exec.scenario.iterationInTest;
  const isCanary = exec.scenario.name === 'canary';
  const phase = isCanary ? 'canary' : (__ENV.PHASE || 'workload');

  if (isCanary) {
    const seed = data.seedOrders[iteration % data.seedOrders.length];
    const startedAt = Date.now();
    const readSucceeded = readOrder(
      seed.operationId,
      seed.payloadSha256,
      'canary-read',
      false,
    );
    const operationId = newGuid();
    const payload = {
      sku: `canary-${runId}-${operationId.slice(0, 8)}`,
      quantity: (iteration % 100) + 1,
      notes: 'synthetic one-second canary',
    };
    const writeSucceeded = writeOrder(operationId, payload, 'canary-write', false);
    const succeeded = readSucceeded && writeSucceeded;
    const durationMs = Date.now() - startedAt;
    canaryTickSuccess.add(succeeded ? 1 : 0);
    canaryTickDuration.add(durationMs);
    emit({
      type: 'canaryTick',
      phase,
      operationId,
      scheduledAtUtc: new Date(startedAt).toISOString(),
      recordedAtUtc: new Date().toISOString(),
      durationMs,
      readSucceeded,
      writeSucceeded,
      success: succeeded,
    });
    return;
  }

  if (iteration % 5 !== 0) {
    const seed = data.seedOrders[iteration % data.seedOrders.length];
    readOrder(seed.operationId, seed.payloadSha256, phase);
    return;
  }

  const operationId = newGuid();
  const payload = {
    sku: `load-${runId}-${operationId.slice(0, 8)}`,
    quantity: (iteration % 100) + 1,
    notes: 'synthetic resilience workload',
  };
  writeOrder(operationId, payload, phase);
}

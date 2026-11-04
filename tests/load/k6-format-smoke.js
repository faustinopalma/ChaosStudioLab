import { Counter } from 'k6/metrics';
import { sleep } from 'k6';
const counter = new Counter('logical_operation_successes');
export const options = {
  scenarios: {
    workload: { executor: 'constant-arrival-rate', rate: 2, timeUnit: '1s', duration: '3s', preAllocatedVUs: 1 },
  },
};
export default function () {
  counter.add(1);
  console.log('LAB_EVENT {"type":"formatSmoke","success":true}');
  if (__ENV.DROP_SMOKE === 'true') {
    sleep(1);
  }
}

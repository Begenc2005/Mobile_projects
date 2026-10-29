import { build } from './app.js';
import { config } from './config.js';
import { startPaymentSweeper } from './orders-service.js';

const app = await build();
startPaymentSweeper(app.log);
await app.listen({ port: config.port, host: config.host });

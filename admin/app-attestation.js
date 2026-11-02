import { initializeAppCheck, ReCaptchaEnterpriseProvider } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-app-check.js";
import { alphaAppCheckSiteKey } from "./security-config.js";
export function configureAdminAppCheck(app) {
  if (!alphaAppCheckSiteKey) return;
  initializeAppCheck(app, { provider: new ReCaptchaEnterpriseProvider(alphaAppCheckSiteKey), isTokenAutoRefreshEnabled: true });
}

// The dashboard SPA loads every plugin's entry and flags one that registers nothing.
(function () {
  var sdk = window.__HERMES_PLUGINS__;
  if (sdk && typeof sdk.register === "function") {
    sdk.register("crew-push", function CrewPush() { return null; });
  }
})();

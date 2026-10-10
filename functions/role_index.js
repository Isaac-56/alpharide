"use strict";

const rideFunctions = require("./index");
const appNotificationFunctions = require("./app_notification_functions");
const roleFunctions = require("./role_functions");
const lifecycleFunctions = require("./lifecycle_functions");
const walletFunctions = require("./wallet_functions");
const adminOpsFunctions = require("./admin_ops_functions");

module.exports = {
  ...appNotificationFunctions,
  ...rideFunctions,
  ...roleFunctions,
  ...lifecycleFunctions,
  ...walletFunctions,
  ...adminOpsFunctions,
};

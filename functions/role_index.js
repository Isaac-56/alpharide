"use strict";

const rideFunctions = require("./index");
const roleFunctions = require("./role_functions");
const lifecycleFunctions = require("./lifecycle_functions");
const walletFunctions = require("./wallet_functions");
const adminOpsFunctions = require("./admin_ops_functions");

module.exports = {
  ...rideFunctions,
  ...roleFunctions,
  ...lifecycleFunctions,
  ...walletFunctions,
  ...adminOpsFunctions,
};

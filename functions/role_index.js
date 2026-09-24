"use strict";

const rideFunctions = require("./index");
const roleFunctions = require("./role_functions");
const lifecycleFunctions = require("./lifecycle_functions");
const walletFunctions = require("./wallet_functions");

module.exports = {
  ...rideFunctions,
  ...roleFunctions,
  ...lifecycleFunctions,
  ...walletFunctions,
};

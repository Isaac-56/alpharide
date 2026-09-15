"use strict";

const rideFunctions = require("./index");
const roleFunctions = require("./role_functions");

module.exports = {
  ...rideFunctions,
  ...roleFunctions,
};

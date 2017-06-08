Package.describe({
  name: 'json-routes-mm',
  version: '2.1.0',
  summary: 'The simplest way to define server-side routes that return JSON',
  git: 'https://github.com/stubailo/meteor-rest'
});

Npm.depends({
  connect: '2.30.2',
  'connect-route': '0.1.5',
});

Package.onUse(function (api) {
  api.versionsFrom('1.0');

  api.use([
    'underscore',
    'webapp',
  ], 'server');

  api.addFiles([
    'json-routes.js',
    'middleware.js',
  ], 'server');

  api.export([
    'JsonRoutes',
    'RestMiddleware',
  ], 'server');
});


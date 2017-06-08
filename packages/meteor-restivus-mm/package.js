Package.describe({
  name: 'restivus-mm',
  summary: 'Create authenticated REST APIs in Meteor 0.9+ via HTTP/HTTPS. Setup CRUD endpoints for Collections.',
  version: '0.8.10',
  git: 'https://github.com/kahmali/meteor-restivus.git'
});


Package.onUse(function (api) {
  // Minimum Meteor version
  api.versionsFrom('METEOR@0.9.0');

  // Meteor dependencies
  api.use('check');
  api.use('coffeescript');
  api.use('underscore');
  api.use('json-routes-mm@2.1.0');

  api.addFiles('lib/auth.coffee', 'server');
  api.addFiles('lib/iron-router-error-to-response.js', 'server');
  api.addFiles('lib/route.coffee', 'server');
  api.addFiles('lib/restivus.coffee', 'server');

  // Exports
  api.export('Restivus', 'server');
});



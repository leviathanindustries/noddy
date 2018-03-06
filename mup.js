// http://meteor-up.com/docs.html
// mup setup to configure the machines mup deploy to deploy the app
// mup reconfig is last steop of deploy, can be run alone, to update env vars, meteor settings, and start script
// mup stop, start, restart, does as expected
// mup logs [-f --tail=50] supports docker logs falgs, gets logs
module.exports = {
  servers: {
    one: {
      host: "10.131.20.129",
      username: "cloo",
      pem: "~/.ssh/id_dsa"
    },
    two: {
      host: "10.131.11.72",
      username: "cloo",
      pem: "~/.ssh/id_dsa"
    }
  },
  meteor: {
    name: 'noddy',
    path: '.',
    docker: {
      image: 'abernix/meteord:node-8.4.0-base'
    },
    servers: {
      one: {
        CID: 1
      },
      two: {
        CID: 2
      }
    },
    buildOptions: {
      serverOnly: true
    },
    env: {
      PORT: 3000,
      ROOT_URL: 'https://api.cottagelabs.com',
      MONGO_URL: 'http://nowhere' // necessary to run a meteor app with no mongo
    },
    deployCheckWaitTime: 60 // 60 is the default
  }
}
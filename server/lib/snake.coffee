
import { spawn } from 'child_process'
import Future from 'fibers/future'

API.add 'snake', get: () -> return API.snake.run() # just handy for testing

API.snake = {}

API.snake.run = (path='snake_example.py', input=[1,2,3], cmd='python', limit=1000) ->
  path = process.env.PWD + '/' + path if path.indexOf('/') isnt 0
  sp = spawn cmd, [path]
  output = ''
  done = false
  sp.stdout.on 'data', (data) -> output += data
  sp.stdout.on 'end', () -> done = true

  sp.stdin.write JSON.stringify input
  sp.stdin.end()
  while not done
    future = new Future()
    Meteor.setTimeout (() -> future.return()), limit
    future.wait()

  return JSON.parse output
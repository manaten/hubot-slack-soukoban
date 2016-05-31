# Description:
#  Start soukoban game on slack.
#
# Commands:
#  soukoban <number> - Start soukoban game.
#
# Author:
#  manaten
#
_ = require 'lodash'
{Promise} = require 'es6-promise'

MAPS = require './maps.coffee'

EMOJIS = {
  up    : 'point_up'
  down  : 'point_down'
  left  : 'point_left'
  right : 'point_right'
  player: 'runner'
  wall  : 'black_large_square'
  box   : 'white_medium_square'
  empty : 'mu'
  goal  : 'small_blue_diamond'
}

Util =
  strToMatrix: (str) -> str.split(/\n/).map((s) -> s.split(''))
  matrixToStr: (matrix) -> matrix.map((a) -> a.join('')).join('\n')
  translocateMatrix: (matrix) -> _.range(matrix[0].length).map((j) -> _.range(matrix.length).map((i) -> matrix[i][j]))
  translocateStr: (str) -> Util.matrixToStr Util.translocateMatrix Util.strToMatrix str
  flipStr: (str) -> Util.matrixToStr Util.strToMatrix(str).map(_.reverse)
  moveRight: (state) ->
    state
    .replace(/[PBg]/g, (s) -> {P: 'ap', B: 'ab', g: 'a.'}[s])
    .replace(/(a?)p(a?)b(a?)\./, '$1.$2p$3b')
    .replace(/(a?)p(a?)\./, '$1.$2p')
    .replace(/a[pb\.]/g, (s) -> {ap: 'P', ab: 'B', 'a.': 'g'}[s])

class SoukobanGame
  constructor: (@state, @number) -> @work = 0
  isClear: -> !(/[gP]/.test @state)
  updateState: (newState) ->
    if newState isnt @state
      @state = newState
      @work = @work + 1
  right: -> @updateState Util.moveRight @state
  up: -> @updateState Util.translocateStr Util.flipStr Util.moveRight Util.flipStr Util.translocateStr @state
  down: -> @updateState Util.translocateStr Util.moveRight Util.translocateStr @state
  left: -> @updateState Util.flipStr Util.moveRight Util.flipStr @state

  print: -> "No.#{@number}\n" + @state.replace(/[#bBpP\.g]/g, (c) ->
    switch c
      when '#' then ":#{EMOJIS.wall}:"
      when '.' then ":#{EMOJIS.empty}:"
      when 'g' then ":#{EMOJIS.goal}:"
      when 'p', 'P' then ":#{EMOJIS.player}:"
      when 'b', 'B' then ":#{EMOJIS.box}:"
  ) + "\ncount: #{@work} #{if @isClear() then 'Game clear!!' else ''}"


module.exports = (robot) ->
  games = {}

  postMessage = (message, channelId) -> new Promise (resolve) ->
    robot.adapter.client._apiCall 'chat.postMessage',
      channel: channelId
      text   : message
      as_user: true
    , (res) -> resolve res

  updateMessage = (message, channelId, ts) -> new Promise (resolve, reject) ->
    robot.adapter.client._apiCall 'chat.update',
      channel: channelId
      text   : message
      ts     : ts
    , (res) ->
      if res.ok then resolve(res) else reject(new Error res.error)

  addReaction = (name, channelId, ts) -> new Promise (resolve) ->
    robot.adapter.client._apiCall 'reactions.add',
      name     : name
      timestamp: ts
      channel  : channelId
    , (res) -> resolve res

  startGame = (game, channelId) ->
    postMessage(game.print(), channelId)
    .then (res) ->
      games[res.ts] = game
      [EMOJIS.left, EMOJIS.up, EMOJIS.down, EMOJIS.right].reduce((curr, name) ->
        curr.then(-> addReaction(name, channelId, res.ts))
      , Promise.resolve())


  robot.adapter.client.on 'raw_message', (message) ->
    robotUserId = robot.adapter.client.getUserByName(robot.name).id
    if (/^reaction_(added|removed)$/.test message.type) && (message.user isnt robotUserId)
      emojiKey = _.findKey EMOJIS, (emoji) -> emoji is message.reaction
      ts = message.item.ts
      channelId = message.item.channel
      game = games[ts]
      if game && /^(up|down|left|right)$/.test emojiKey
        game[emojiKey]()
        updateMessage(game.print(), channelId, ts)
        .catch (e) ->
          if e.message is 'edit_window_closed'
            delete games[ts]
            startGame(game, channelId)
          else
            Promise.reject e

  robot.hear /soukoban[^\d]*(\d*)/, (msg) ->
    unless robot.adapter?.client?._apiCall?
      msg.send 'This script runs only with hubot-slack.'
      return

    number = msg.match[1] or Math.floor(Math.random() * MAPS.length)
    channelId = robot.adapter.client.getChannelGroupOrDMByName(msg.envelope.room)?.id
    game = new SoukobanGame(MAPS[number], number)
    startGame(game, channelId)

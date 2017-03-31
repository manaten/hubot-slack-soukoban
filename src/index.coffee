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
  up          : 'point_up'
  down        : 'point_down'
  left        : 'point_left'
  right       : 'point_right'
  player      : 'runner'
  playerOnGoal: 'runner'
  wall        : 'black_large_square'
  box         : 'white_circle'
  boxOnGoal   : 'large_blue_circle'
  empty       : 'mu'
  goal        : 'small_blue_diamond'
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
      when 'b' then ":#{EMOJIS.box}:"
      when 'B' then ":#{EMOJIS.boxOnGoal}:"
      when 'p' then ":#{EMOJIS.player}:"
      when 'P' then ":#{EMOJIS.playerOnGoal}:"
  ) + "\ncount: #{@work} #{if @isClear() then '*Game clear!!*' else ''}"


module.exports = (robot) ->
  games = {}

  startGame = (game, channelId) ->
    robot.adapter.client.web.chat.postMessage(channelId, game.print(), {as_user: true})
    .then (res) ->
      games[res.ts] = game
      [EMOJIS.left, EMOJIS.up, EMOJIS.down, EMOJIS.right].reduce((curr, name) ->
        curr.then(-> robot.adapter.client.web.reactions.add(name, {channel: channelId, timestamp: res.ts}))
      , Promise.resolve())

  pressButton = (message) ->
    robotUserId = robot.adapter.client.rtm.dataStore.getUserByName(robot.name).id
    if message.user is robotUserId
      return
    emojiKey = _.findKey EMOJIS, (emoji) -> emoji is message.reaction
    ts = message.item.ts
    channelId = message.item.channel
    game = games[ts]
    unless game && /^(up|down|left|right)$/.test emojiKey
      return
    if game.isClear()
      return
    game[emojiKey]()
    robot.adapter.client.web.chat.update(ts, channelId, game.print())
    .catch (e) ->
      if e.message is 'edit_window_closed' and games[ts]?
        delete games[ts]
        startGame(game, channelId)
      else
        robot.logger.error e

  robot.adapter.client?.rtm?.on? 'reaction_added', pressButton
  robot.adapter.client?.rtm?.on? 'reaction_removed', pressButton

  robot.hear /soukoban[^\d]*(\d*)/, (msg) ->
    unless robot.adapter.client?.web?
      msg.send 'This script runs only with hubot-slack.'
      return

    number = msg.match[1] or Math.floor(Math.random() * MAPS.length)
    channelId = msg.envelope.room
    game = new SoukobanGame(MAPS[number], number)
    startGame(game, channelId)

# Description:
#  Start soukoban game on slack.
#
# Commands:
#  soukoban - Start soukoban game.
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

Util = {
  strToMatrix: (str) -> str.split(/\n/).map((s) -> s.split(''))
  matrixToStr: (matrix) -> matrix.map((a) -> a.join('')).join('\n')
  flipStr: (str) -> Util.matrixToStr Util.strToMatrix(str).map(_.reverse)
  translocateMatrix: (matrix) ->
    _.range(matrix[0].length).map((j) ->
      _.range(matrix.length).map((i) -> matrix[i][j])
    )
  translocateStr: (str) -> Util.matrixToStr Util.translocateMatrix Util.strToMatrix str

  moveRight: (state) ->
    state
    .replace(/[pP][bB][\.g]/, (cs) ->
      cs.replace(/./g, (c) ->
        switch c
          when 'p' then '.'
          when 'P' then 'g'
          when 'b' then 'p'
          when 'B' then 'P'
          when '.' then 'b'
          when 'g' then 'B'
      )
    )
    .replace(/[pP][\.g]/, (cs) ->
      cs.replace(/./g, (c) ->
        switch c
          when 'p' then '.'
          when 'P' then 'g'
          when '.' then 'p'
          when 'g' then 'P'
      )
    )
}

class SoukobanGame
  constructor: (@state) ->
    @work = 0

  isClear: -> !(/[gP]/.test @state)

  print: -> @state.replace(/[#bBpP\.g]/g, (c) ->
      switch c
        when '#' then ":#{EMOJIS.wall}:"
        when '.' then ":#{EMOJIS.empty}:"
        when 'g' then ":#{EMOJIS.goal}:"
        when 'p', 'P' then ":#{EMOJIS.player}:"
        when 'b', 'B' then ":#{EMOJIS.box}:"
    ) + "\ncount: #{@work} #{if @isClear() then 'Game clear!!' else ''}"

  updateState: (newState) ->
    if newState isnt @state
      @state = newState
      @work = @work + 1

  right: -> @updateState Util.moveRight @state
  up: -> @updateState Util.translocateStr Util.flipStr Util.moveRight Util.flipStr Util.translocateStr @state
  down: -> @updateState Util.translocateStr Util.moveRight Util.translocateStr @state
  left: -> @updateState Util.flipStr Util.moveRight Util.flipStr @state

module.exports = (robot) ->
  games = {}

  postMessage = (message, channelId) -> new Promise (resolve) ->
    robot.adapter.client._apiCall 'chat.postMessage',
      channel: channelId
      text   : message
      as_user: true
    , (res) -> resolve res

  updateMessage = (message, channelId, ts) -> new Promise (resolve) ->
    robot.adapter.client._apiCall 'chat.update',
      channel: channelId
      text   : message
      ts     : ts
    , (res) -> resolve res

  addReaction = (name, channelId, ts) -> new Promise (resolve) ->
    robot.adapter.client._apiCall 'reactions.add',
      name     : name
      timestamp: ts
      channel  : channelId
    , (res) -> resolve res

  robot.adapter.client.on 'raw_message', (message) ->
    robotUserId = robot.adapter.client.getUserByName(robot.name).id
    if (/^reaction_(added|removed)$/.test message.type) && (message.user isnt robotUserId)
      emojiKey = _.findKey EMOJIS, (emoji) -> emoji is message.reaction
      ts = message.item.ts
      channelId = message.item.channel
      game = games[ts]
      if game && /^(up|down|left|right)$/.test emojiKey
        game[emojiKey]()
        updateMessage game.print(), channelId, ts

  robot.hear /soukoban/, (msg) ->
    unless robot.adapter?.client?._apiCall?
      msg.send 'This script runs only with hubot-slack.'
      return

    chId = robot.adapter.client.getChannelGroupOrDMByName(msg.envelope.room)?.id
    game = new SoukobanGame(msg.random MAPS)
    postMessage(game.print(), chId)
    .then (res) ->
      games[res.ts] = game
      [EMOJIS.left, EMOJIS.up, EMOJIS.down, EMOJIS.right].reduce((curr, name) ->
        curr.then(-> addReaction(name, chId, res.ts))
      , Promise.resolve())

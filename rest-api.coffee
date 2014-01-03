__ = require('i18n').__
Q = require 'q'
fs = require 'fs'

module.exports = (env) ->

  class RestFrontend extends env.plugins.Plugin
    config: null

    init: (app, framework, @config) =>
      
      sendSuccessResponse = (res, data = {}) =>
        data.success = true
        res.send 200, data

      sendErrorResponse = (res, error, statusCode = 400) =>
        message = null
        if error instanceof Error
          message = error.message
          env.logger.error error.message
          env.logger.debug error.stack
        else
          message = error
        res.send statusCode, {success: false, error: message}

      app.get "/api/actuator/:actuatorId/:actionName", (req, res, next) =>
        actuator = framework.getActuatorById req.params.actuatorId
        if actuator?
          #TODO: add parms support
          if actuator.hasAction req.params.actionName
            result = actuator[req.params.actionName]() 
            Q.when(result,  =>
              sendSuccessResponse res
            ).catch( (error) =>
              sendErrorResponse res, error, 500
            ).done()
          else
            sendErrorResponse res, 'actuator hasn\'t that action'
        else sendErrorResponse res, 'actuator not found'


      app.post "/api/rule/:ruleId/update", (req, res, next) =>
        ruleId = req.params.ruleId
        ruleString = req.body.rule
        unless ruleId? then return sendErrorResponse res, 'No ruleId given', 400
        unless ruleString? then return sendErrorResponse res, 'No rule given', 400
        framework.ruleManager.updateRuleByString(ruleId, ruleString).then( =>
          sendSuccessResponse res
        ).catch( (error) =>
          sendErrorResponse res, error, 406
        ).done()


      app.post "/api/rule//add", (req, res, next) =>
        sendErrorResponse res, 'No id given', 400
        
      app.post "/api/rule/:ruleId/add", (req, res, next) =>
        ruleId = req.params.ruleId
        ruleText = req.body.rule
        framework.ruleManager.addRuleByString(ruleId, ruleText).then( =>
          sendSuccessResponse res
        ).catch( (error) =>
          sendErrorResponse res, error, 406
        ).done()

      app.get "/api/rule/:ruleId/remove", (req, res, next) =>
        ruleId = req.params.ruleId
        try
          framework.ruleManager.removeRule ruleId
          sendSuccessResponse res
        catch error
          sendErrorResponse res, error, 500

      app.get "/api/messages", (req, res, next) =>
        memoryTransport = env.logger.transports.memory
        sendSuccessResponse res, { messages: memoryTransport.getBuffer() }

      app.get "/api/list/actuators", (req, res, next) =>
        actuatorList = for id, a of framework.actuators 
          id: a.id, name: a.name
        sendSuccessResponse res, { actuators: actuatorList }

      app.get "/api/list/sensors", (req, res, next) =>
        sensorList = for id, s of framework.sensors 
          id: s.id, name: s.name
        sendSuccessResponse res, { sensors: sensorList}

      app.get "/api/plugins/installed", (req, res, next) =>
        framework.pluginManager.getInstalledPlugins().then( (plugins) =>

          pluginList = 
            for name in plugins
              packageJson = JSON.parse(
                fs.readFileSync("./node_modules/#{name}/package.json", 'utf-8')
              )
              name = name.replace 'pimatic-', ''
              loadedPlugin = framework.getPlugin name
              listEntry = 
                name: name
                active: loadedPlugin?
                description: packageJson.description
                version: packageJson.version
                homepage: packageJson.homepage

          sendSuccessResponse res, { plugins: pluginList}
        ).catch( (error) =>
          sendErrorResponse res, error, 406
        ).done()


      app.get "/api/plugins/search", (req, res, next) =>
        framework.pluginManager.searchForPlugins().then( (plugins) =>
          pluginList =
            for k, p of plugins 
              name = p.name.replace 'pimatic-', ''
              loadedPlugin = framework.getPlugin name
              installed = fs.existsSync "#{framework.maindir}/node_modules/#{p.name}" 
              listEntry =
                name: name
                description: p.description
                version: p.version
                installed: installed
                active: loadedPlugin?


          sendSuccessResponse res, { plugins: pluginList}
        ).catch( (error) =>
          sendErrorResponse res, error, 406
        ).done()
        
      app.post "/api/plugins/add", (req, res, next) =>
        plugins = req.body.plugins
        unless plugins? then return sendErrorResponse res, "No plugins given", 400
        pluginNames = (p.plugin for p in framework.config.plugins)
        added = []
        for p in plugins
          unless p in pluginNames
            framework.config.plugins.push
              plugin: p
            added.push p
        framework.saveConfig()
        sendSuccessResponse res, added: added

      app.post "/api/plugins/remove", (req, res, next) =>
        plugins = req.body.plugins
        unless plugins? then return sendErrorResponse res, "No plugins given", 400
        removed = []
        for p, i in framework.config.plugins
          if p.plugin in plugins
            framework.config.plugins.splice(i, 1)
            removed.push p.plugin
        framework.saveConfig()
        sendSuccessResponse res, removed: removed
        
  return new RestFrontend
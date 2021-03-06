@objc(Webserver) class Webserver : CDVPlugin {
    // Timeout in seconds
    let TIMEOUT: Int = 60 * 3 * 1000000

    var webServer: GCDWebServer = GCDWebServer()
    var responses: Dictionary<String, Any> = [:]
    var onRequestCommand: CDVInvokedUrlCommand? = nil

    override func pluginInitialize() {
        self.webServer = GCDWebServer()
        self.onRequestCommand = nil
        self.responses = [:]
        self.initHTTPRequestHandlers()
    }

    func requestToRequestDict(requestUUID: String, request: GCDWebServerRequest) -> Dictionary<String, Any> {
        let dataRequest = request as! GCDWebServerDataRequest
        var body = ""

        if dataRequest.hasBody() {
            body = String(data: dataRequest.data, encoding: String.Encoding(rawValue: String.Encoding.utf8.rawValue)) ?? ""
        }

        return [
            "requestId": requestUUID,
            "body": body,
            "headers": dataRequest.headers,
            "method": dataRequest.method,
            "path": dataRequest.url.path,
            "query": dataRequest.url.query ?? ""
        ]
    }

    func processRequest(request: GCDWebServerRequest, completionBlock: GCDWebServerCompletionBlock) {
        var timeout = 0
        // Fetch data as GCDWebserverDataRequest
        let requestUUID = UUID().uuidString
        // Transform it into an dictionary for the javascript plugin
        let requestDict = self.requestToRequestDict(requestUUID: requestUUID, request: request)

        // Do a call to the onRequestCommand to inform the JS plugin
        if (self.onRequestCommand != nil) {
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: requestDict)
            pluginResult?.setKeepCallbackAs(true)
            self.commandDelegate.send(
                pluginResult,
                callbackId: self.onRequestCommand?.callbackId
            )
        }

        // Here we have to wait until the javascript block fetches the message and do a response
        while self.responses[requestUUID] == nil {
            timeout += 1000
            usleep(1000)
        }

        // We got the dict so put information in the response
        let responseDict = self.responses[requestUUID] as! Dictionary<AnyHashable, Any>
        let response = GCDWebServerDataResponse(text: responseDict["body"] as! String)
        response?.statusCode = responseDict["status"] as! Int

        for (key, value) in (responseDict["headers"] as! Dictionary<String, String>) {
            response?.setValue(value, forAdditionalHeader: key)
        }

        // Complete the async response
        completionBlock(response!)
    }

    func onRequest(_ command: CDVInvokedUrlCommand) {
        self.onRequestCommand = command
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_NO_RESULT)
        pluginResult?.setKeepCallbackAs(true)
        self.commandDelegate.send(
            pluginResult,
            callbackId: self.onRequestCommand?.callbackId
        )
    }

    func initHTTPRequestHandlers() {
        self.webServer.addHandler(
            match: {
                (requestMethod, requestURL, requestHeaders, urlPath, urlQuery) -> GCDWebServerRequest? in
                    return GCDWebServerDataRequest(method: requestMethod, url: requestURL, headers: requestHeaders, path: urlPath, query: urlQuery)
            },
            asyncProcessBlock: self.processRequest
        )
    }

    func sendResponse(_ command: CDVInvokedUrlCommand) {
        self.responses[command.argument(at: 0) as! String] = command.argument(at: 1)
    }

    func start(_ command: CDVInvokedUrlCommand) {
        var port = 8080
        let portArgument = command.argument(at: 0)

        if portArgument != nil {
            port = portArgument as! Int
        }
        self.webServer.start(withPort: UInt(port), bonjourName: nil)
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }

    func stop(_ command: CDVInvokedUrlCommand) {
        if self.webServer.isRunning {
            self.webServer.stop()
        }
        print("Stopping webserver")
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
}

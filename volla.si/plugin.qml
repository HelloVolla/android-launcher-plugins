import QtQuick 2.12
import AndroidNative 1.0 as AN

// Volla supportive intelligence: everything about the on-device assistant
// (laya decisions and LLM answers) lives here. Springboard only calls:
//   activate()             - the Springboard page became visible
//   reset()                - the text input was cleared
//   inputProcessed(input)  - the worker rebuilt the list for a new input
// plus the generic plugin functions processInput() and executeInput().
QtObject{
    id: si

    property var metadata: {
        'id': 'volla_supportive_intelligence',
        'name': 'Supportive Intelligence',
        'description': "On-device assistant for handling user queries and providing intelligent responses.",
        'version': '0.1.0',
        'minLauncherVersion': 3,
        'maxLauncherVersion': 100,
        'resources': [ ]
    }
    property var config: loadSIConfig(assistant.configUrl)
    property string assistantPrompt: ""
    property bool assistantThinking: false
    property var assistantDecision

    property var sourceItems: ({})
    property string decidedText: ""
    property string lastInput: ""

    function init() {
        if (!downloader.modelsReady())
            downloader.offerOnce()
    }

    function activate() {
        if (downloader.modelsReady())
            llm.startAssistant()
    }

    function reset() {
        decisionTimer.stop()
        assistantThinking = false
        assistantDecision = undefined
        decidedText = ""
        lastInput = ""
        sourceItems["laya"] = []
        sourceItems["ask"] = []
        sourceItems["download"] = []
        llm.clearAssistant()
    }

    function inputProcessed(input) {
        var text = input.trim()
        var contactPrefix = input.indexOf("@") === 0
        var deleted = input.length < lastInput.length
        lastInput = input

        if (text.length === 0 || contactPrefix || deleted) {
            decisionTimer.stop()
            if (assistantDecision !== undefined) {
                assistantDecision = undefined
                sourceItems["laya"] = []
            }
            decidedText = ""
        }
        if (text !== assistantPrompt)
            llm.clearAssistant()

        if (!downloader.modelsReady()) {
            sourceItems["download"] = assistant.available && !contactPrefix && text.length > 0
                    ? [downloader.item()] : []
            listModel.insertItems(sourceItems["download"])
            return
        }

        sourceItems["ask"] = assistant.available && !contactPrefix && text.length > 2
                ? [llm.askItem()] : []
        listModel.insertItems(sourceItems["ask"])
        listModel.insertItems(sourceItems["laya"] || [])
        listModel.insertItems(sourceItems["assistant"] || [])

        if (text.length > 0 && !contactPrefix && text !== decidedText) {
            decidedText = text
            decisionTimer.stop()
            if (assistant.available && assistant.ready) {
                decisionTimer.prompt = text
                decisionTimer.restart()
            }
        }
    }

    function processInput(input, callback){

        callback(true, [], metadata.id)
    }

    function executeInput(input, functionId, object){
        var parts = String(functionId).split('.')
        var module = modules.filter(function (m) {return m.key === parts[0]})[0]
        if (module && typeof module.execute === "function")
            return module.execute(parts[1], input, object)
        return false
    }


    property Connections assistantConnections: Connections {
        target: assistant

        onReadyChanged: {
            console.log("SI | Assistant ready: " + assistant.ready)
            if (si.assistantThinking && assistant.ready)
                si.llm.setAssistantItems([si.llm.assistantItem(qsTr("Thinking..."))])
        }

        onResponse: {
            console.log("SI | Assistant replied: " + text)
            si.assistantThinking = false
            if (si.assistantPrompt === "")
                return
            si.llm.setAssistantItems(text.trim() !== "" ? [si.llm.assistantItem(text.trim())] : [])
        }

        onDecision: {
            console.log("SI | Assistant decided: " + answer.key
                        + " (confidence " + answer.confidence + ")")
            var decision = JSON.parse(JSON.stringify(answer))


            if (si.clock.getAvailableActions().indexOf(decision.key) >= 0) {
                if(decision.key === "set_alarm" || decision.key === "set_timer"){
                    decision.time = si.clock.lookForTime(decision.prompt)
                }
                si.clock.actionChosen(decision)
                return
            }

            if (decision.key === si.dialer.key)
                decision.callees = si.dialer.contactsMentionedIn(decision.prompt).slice(0, 3)
            si.assistantDecision = decision
            si.setSourceItems("laya", si.router.layaItems(decision))
            if (decision.key === si.clock.key){
                si.clock.checkForAlarmType(decision.prompt)
            }
        }

        onError: {
            console.warn("SI | Assistant error: " + message)
            si.assistantThinking = false
            si.llm.clearAssistant()
            mainView.showToast(message)
        }
    }

    property Connections dispatcherConnections: Connections {
        target: AN.SystemDispatcher
        onDispatched: {
            if (type === "volla.launcher.gotSiAlarmsResponse")
                si.clock.alarmsReceived(message.alarms)
        }
    }

    onAssistantThinkingChanged: mainView.updateSpinner(assistantThinking)

    property Timer decisionTimer: Timer {
        property string prompt: ""
        interval: 400
        onTriggered: si.router.decide(prompt)
    }

    function setSourceItems(source, items) {
        listModel.removeItems(sourceItems[source] || [])
        sourceItems[source] = items
        listModel.insertItems(items)
    }

    function loadSIConfig(fileUrl) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", fileUrl, false)
        xhr.send()
        if ((xhr.status === 200 || xhr.status === 0) && xhr.responseText.length > 0) {
            try {
                var config = JSON.parse(xhr.responseText)
                if (config.available_plugins !== undefined && config.plugin_descriptions !== undefined)
                    return config
                console.warn("SI | Invalid SI config in " + fileUrl)
            } catch (error) {
                console.warn("SI | Could not parse " + fileUrl + ": " + error)
            }
        } else {
            console.warn("SI | Could not read " + fileUrl + " (status " + xhr.status + ")")
        }
        return null
    }

    
    function getAvailablePlugins() {
        if (!config || !config.available_plugins || !config.plugin_descriptions)
            return []
        return config.available_plugins.filter(function (key) {
            return config.plugin_descriptions[key] !== undefined
        })
    }

    function getPluginDescription(){
        return getAvailablePlugins().map(function (key) {return config.plugin_descriptions[key]})
    }

    function getRule() {
        return config && config.rule ? config.rule
                                     : "choose the application that may helpful for user"
    }

    function getNumOptions(){
        return getAvailablePlugins().length
    }

    property QtObject router: QtObject{
        
        function layaItems(decision) {
            var items = []
            var add = function (text, action, actionObj) {
                var item = {"text": text, "action": action, "category": listModel.category.Function,
                            "source": "laya", "isFirstSuggestion": false}
                if (actionObj !== undefined)
                    item.actionObj = actionObj
                items.push(item)
            }
            if (decision.callees !== undefined) {
                for (var i = 0; i < decision.callees.length; i++)
                    add(mainView.actionName.CallContact + " " + decision.callees[i]["name"],
                        mainView.actionType.CallContact, decision.callees[i])
            }
            if (decision.time && (decision.clockAction === "set_alarm" || decision.clockAction === "set_timer")) {
                var h = parseInt(decision.time.hour, 10)
                var m = parseInt(decision.time.minutes, 10)
                if (isNaN(h)) h = 0
                if (isNaN(m)) m = 0
                var label = (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
                if (decision.clockAction === "set_alarm")
                    add(mainView.actionName.SetAlarm + " " + label,
                        mainView.actionType.SetAlarm, {"hour": h, "minutes": m})
                else
                    add(mainView.actionName.SetTimer + " " + label,
                        mainView.actionType.SetTimer, {"hour": h, "minutes": m})
            }
            if (decision.clockAction === "dismiss_alarm" && si.clock.siAlarms !== undefined) {
                // One option per time; dismissing it dismisses every SI alarm at that time.
                var shown = {}
                for (var a = 0; a < si.clock.siAlarms.length; a++) {
                    var alarm = si.clock.siAlarms[a]
                    var time = si.clock.formatTime(alarm.hour, alarm.minutes)
                    if (shown[time])
                        continue
                    shown[time] = true
                    add(mainView.actionName.DismissAlarm + " " + time,
                        mainView.actionType.DismissAlarm,
                        {"hour": alarm.hour, "minutes": alarm.minutes})
                }
            }
            if (decision.key === si.clock.key)
                add(mainView.actionName.OpenClock, mainView.actionType.OpenClock,
                    decision.clockAction !== undefined ? {"clockAction": decision.clockAction} : undefined)
            else if (decision.key === si.dialer.key)
                add(mainView.actionName.ShowDialer, mainView.actionType.ShowDialer)
            else if (decision.key === si.llm.key)
                items.push(si.llm.askItem("laya"))
            return items
        }

        function decide(input) {
            if (si.getNumOptions() > 0)
                assistant.decide(input, si.getAvailablePlugins(), si.getPluginDescription(),
                                 si.getRule(), si.getNumOptions())
        }

        function chooseAction(input, availableActions, actionDescription, rule, numActions){
            if(numActions > 0)
                assistant.decide(input, availableActions, actionDescription, rule, numActions)
        }
    }

    property QtObject clock: QtObject{
        readonly property string key: "alarm"
        function suggestions(decision, input){
            return []
        }

        function getAvailableActions(){
            var clockActions = si.config ? si.config.clock_actions : undefined
            if (!clockActions || !clockActions.actions || !clockActions.description)
                return []
            return clockActions.actions.filter(function (action) {
                return clockActions.description[action] !== undefined
            })
        }

        function getActionDescriptions(){
            return getAvailableActions().map(function (action) {
                return si.config.clock_actions.description[action]
            })
        }

        function getActionRule(){
            var clockActions = si.config ? si.config.clock_actions : undefined
            return clockActions && clockActions.rule ? clockActions.rule
                                                     : "choose the clock action the user asks for"
        }

        function getNumActions(){
            return getAvailableActions().length
        }


        function checkForAlarmType(prompt){
            var actions = getAvailableActions()
            si.router.chooseAction(prompt, actions, getActionDescriptions(),
                                   getActionRule(), actions.length)
        }

        function actionChosen(decision) {
            var current = si.assistantDecision
            if (current === undefined || current.key !== key || current.prompt !== decision.prompt) {
                console.log("SI | Clock action for old input ignored: " + decision.prompt)
                return
            }
            console.log("SI | Clock action: " + decision.key + " (confidence " + decision.confidence + ")")
            current.clockAction = decision.key
            current.clockActionConfidence = decision.confidence
            current.time = decision.time
            si.assistantDecision = current
            if (decision.key === "dismiss_alarm") {
                si.clock.siAlarms = undefined
                AN.SystemDispatcher.dispatch("volla.launcher.getSiAlarmsAction", {})
            }
            si.setSourceItems("laya", si.router.layaItems(current))
        }


        property var siAlarms: undefined

        function alarmsReceived(alarms) {
            si.clock.siAlarms = alarms || []
            var current = si.assistantDecision
            if (current === undefined || current.clockAction !== "dismiss_alarm")
                return
            if (si.clock.siAlarms.length === 0)
                mainView.showToast(qsTr("There are no alarms set by SI"))
            si.setSourceItems("laya", si.router.layaItems(current))
        }

        function formatTime(hour, minutes) {
            return (hour < 10 ? "0" : "") + hour + ":" + (minutes < 10 ? "0" : "") + minutes
        }

        // Finds a time or duration in the prompt; returns { hour, minutes } or null.
        // Checked in this order:
        //   1. clock time "7:30", "07:30", "19.45", "7:30 pm"
        //   2. duration   "2 min", "1h 30m", "90 minutes" (90 min -> 1:30)
        //   3. clock time "7", "7 am", "7h30"
        function lookForTime(prompt) {
            var text = " " + prompt.toLowerCase() + " "

            var clock = text.match(/[^\d:.](\d{1,2})[:.](\d{2})(?![\d:]|\.\d)\s*(a\.?\s?m\.?|p\.?\s?m\.?)?/)
            if (clock) {
                var time = clockTime(clock[1], clock[2], clock[3])
                if (time)
                    return time
            }

            // Separators removed; a "." would otherwise break "7 a.m." and "2 min.".
            var words = text.replace(/[\s.,!?;"'()]+/g, " ")

            var hours = words.match(/\b(\d{1,2})\s*(?:h|hr|hrs|hour|hours)\b/)
            var mins = words.match(/\b(\d{1,3})\s*(?:m|min|mins|minute|minutes)\b/)
            if (hours || mins) {
                var total = (hours ? parseInt(hours[1], 10) * 60 : 0) + (mins ? parseInt(mins[1], 10) : 0)
                if (total === 0 || total >= 24 * 60)
                    return null
                return { hour: Math.floor(total / 60), minutes: total % 60 }
            }

            var plain = words.match(/\b(\d{1,2})(?:h(\d{2}))?\s*(a ?m|p ?m)?\b/)
            return plain ? clockTime(plain[1], plain[2] || "0", plain[3]) : null
        }

        // hour/minutes as strings, suffix "am"/"pm" in any spelling or empty.
        function clockTime(hourText, minutesText, suffix) {
            var hour = parseInt(hourText, 10)
            var minutes = parseInt(minutesText, 10)
            var ampm = suffix ? suffix.replace(/[.\s]/g, "") : ""
            if (ampm === "pm" && hour < 12) hour += 12
            if (ampm === "am" && hour === 12) hour = 0
            if (hour > 23 || minutes > 59)
                return null
            return { hour: hour, minutes: minutes }
        }

    }

    property QtObject dialer: QtObject{
        readonly property string key: "call"
        function editDistance(a, b) {
            var m = a.length
            var n = b.length
            var dp = []
            for (var i = 0; i <= m; i++) {
                dp.push([i])
                for (var j = 1; j <= n; j++)
                    dp[i].push(i === 0 ? j : 0)
            }
            for (i = 1; i <= m; i++) {
                for (j = 1; j <= n; j++) {
                    var cost = a[i - 1] === b[j - 1] ? 0 : 1
                    dp[i][j] = Math.min(dp[i - 1][j] + 1,
                                        dp[i][j - 1] + 1,
                                        dp[i - 1][j - 1] + cost)
                }
            }
            return dp[m][n]
        }

        function isMisspelling(word, name) {
            if (word.length < 4 || name.length < 4)
                return false
            var allowed = name.length >= 7 ? 2 : 1
            return Math.abs(word.length - name.length) <= allowed && editDistance(word, name) <= allowed
        }

        function contactsMentionedIn(prompt) {
            var text = " " + prompt.toLowerCase().replace(/[\s.,!?;:"'()]+/g, " ") + " "
            var words = text.trim().split(" ")
            var phoneKeys = ["phone.mobile", "phone.home", "phone.work", "phone.other"]
            var contacts = mainView.getContacts()
            var matches = []
            for (var c = 0; c < contacts.length; c++) {
                var contact = contacts[c]
                if (contact["name"] === undefined)
                    continue
                var hasPhone = phoneKeys.some(function (key) {
                    return contact[key] !== undefined && contact[key].length > 0
                })
                if (!hasPhone)
                    continue
                var name = contact["name"].toLowerCase().trim()
                var nameParts = name.split(/\s+/)
                var score = 0
                if (text.indexOf(" " + name + " ") >= 0) {
                    score = 3
                } else if (nameParts.some(function (part) {
                    return part.length > 1 && text.indexOf(" " + part + " ") >= 0
                })) {
                    score = 2
                } else if (words.some(function (word) {
                    return word.length > 2 && nameParts.some(function (part) {
                        return part.indexOf(word) === 0
                    })
                })) {
                    score = 1
                } else if (words.some(function (word) {
                    return nameParts.some(function (part) {
                        return isMisspelling(word, part)
                    })
                })) {
                    score = 0.5
                }
                if (score > 0)
                    matches.push({"contact": contact, "score": score})
            }
            matches.sort(function (a, b) { return b.score - a.score })
            return matches.filter(function (m) { return m.score === matches[0].score })
                        .map(function (m) { return JSON.parse(JSON.stringify(m.contact)) })
        }

        function suggestions(decision, input){
            return []
        }
    }

    property QtObject llm: QtObject {
        readonly property string key: "LLM"

        // Returns true so Springboard keeps the question in the input.
        function execute(functionName, input, object) {
            if (functionName === "ask") {
                askAssistant(input)
                return true
            }
            return false
        }

        function startAssistant() {
            if (!assistant.available)
                return
            console.log("SI | Preloading assistant")
            assistant.init()
        }

        function askAssistant(prompt) {
            console.log("SI | Ask assistant: " + prompt)
            si.assistantPrompt = prompt.trim()
            si.assistantThinking = true
            setAssistantItems([assistantItem(assistant.ready ? qsTr("Thinking...")
                                                            : qsTr("Starting the assistant..."))])
            assistant.ask(prompt)
        }

        function askItem(source) {
            return {
                "text": mainView.actionName.AskAssistant,
                "action": mainView.actionType.AskAssistant,
                "actionObj": {"pluginId": si.metadata.id, "functionId": key + ".ask"},
                "category": listModel.category.Function,
                "source": source !== undefined ? source : "ask",
                "isFirstSuggestion": false
            }
        }

        function assistantItem(text) {
            return {
                "text": text,
                "action": mainView.actionType.LiveContentPlugin,
                "actionObj": {"pluginId": si.metadata.id, "link": ""},
                "category": listModel.category.LiveContent,
                "source": "assistant",
                "isFirstSuggestion": false
            }
        }

        function setAssistantItems(items) {
            si.setSourceItems("assistant", items)
        }

        function clearAssistant() {
            si.assistantPrompt = ""
            si.setSourceItems("assistant", [])
        }
    }

    // Downloads the models through the launcher's modelHandler
    // (libmodel_handler). Asks for consent first and warns on mobile data.
    property QtObject downloader: QtObject {
        readonly property string key: "download"
        property bool hasHandler: typeof modelHandler !== "undefined"
        property var store: Qt.createQmlObject(
            'import Qt.labs.settings 1.0; Settings { category: "volla_si"; property bool downloadOffered: false }',
            si, "siSettings")

        function modelsReady() {
            return !hasHandler || modelHandler.installed
        }

        function sizeText() {
            var mb = modelHandler.missingBytes / (1024 * 1024)
            return mb >= 1024 ? (mb / 1024).toFixed(1) + " GB" : Math.max(1, Math.round(mb)) + " MB"
        }

        function item() {
            var text = modelHandler.downloading
                    ? qsTr("Downloading assistant") + " " + Math.floor(modelHandler.progress * 100) + "% · " + qsTr("tap to cancel")
                    : qsTr("Download assistant") + " (" + sizeText() + ")"
            return {
                "text": text,
                "action": mainView.actionType.AskAssistant,
                "actionObj": {"pluginId": si.metadata.id,
                              "functionId": key + (modelHandler.downloading ? ".cancel" : ".start")},
                "category": listModel.category.Function,
                "source": "download",
                "isFirstSuggestion": false
            }
        }

        function refreshItem() {
            if ((si.sourceItems["download"] || []).length > 0)
                si.setSourceItems("download", modelsReady() ? [] : [item()])
        }

        function execute(functionName, input, object) {
            if (functionName === "start")
                offer()
            else if (functionName === "cancel")
                modelHandler.cancel()
            return true
        }

        // Offer the download only once automatically (when the skill is
        // enabled); afterwards the user starts it from the Springboard item.
        function offerOnce() {
            if (!hasHandler || !assistant.available || store.downloadOffered || modelHandler.downloading)
                return
            store.downloadOffered = true
            offer()
        }

        function offer() {
            if (!hasHandler || modelHandler.downloading)
                return
            modelHandler.refresh()
            if (modelHandler.installed)
                return
            var metered = modelHandler.isMeteredNetwork()
            var text = qsTr("Supportive Intelligence needs to download its models (%1). ")
                        .arg(sizeText()).arg(modelHandler.directory)
            if (metered)
                text += "\n\n" + qsTr("You are on mobile data. It is recommended to wait for Wi-Fi.")
            var dialog = Qt.createQmlObject('
                import QtQuick 2.12
                import QtQuick.Controls 2.5
                Dialog {
                    property alias message: label.text
                    property string acceptText
                    anchors.centerIn: parent
                    width: parent.width * 0.85
                    modal: true
                    title: qsTr("Download assistant")
                    Label { id: label; width: parent.width; wrapMode: Text.WordWrap }
                    footer: DialogButtonBox {
                        Button { text: qsTr("Later"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole; flat: true }
                        Button { text: acceptText; DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole; flat: true }
                    }
                    onClosed: destroy()
                }', mainView, "siDownloadDialog")
            dialog.message = text
            dialog.acceptText = metered ? qsTr("Use mobile data") : qsTr("Download")
            dialog.accepted.connect(function () {
                if (modelHandler.download())
                    mainView.showToast(qsTr("Downloading the assistant models"))
                refreshItem()
            })
            dialog.open()
        }
    }

    property Connections modelConnections: Connections {
        target: si.downloader.hasHandler ? modelHandler : null
        ignoreUnknownSignals: true

        onProgressChanged: si.downloader.refreshItem()
        onDownloadingChanged: si.downloader.refreshItem()

        onFinished: {
            console.log("SI | Models installed")
            si.config = si.loadSIConfig(assistant.configUrl)
            si.setSourceItems("download", [])
            mainView.showToast(qsTr("The assistant is ready"))
            if (springBoard.isCurrentPage)
                si.llm.startAssistant()
        }

        onFailed: {
            console.warn("SI | Model download stopped: " + message)
            if (!cancelled)
                mainView.showToast(qsTr("Assistant download failed") + ": " + message)
            si.downloader.refreshItem()
        }
    }

    property var modules: [clock, dialer, llm, downloader]
}

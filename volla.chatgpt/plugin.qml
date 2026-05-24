import QtQuick 2.12;

QtObject {

    property var metadata: {
        'id': 'volla_chatgpt',
        'name': 'ChatGPT',
        'description': 'This plugin integrates ChatGPT for AI-powered responses directly from the springboard',
        'version': 0.1,
        'minLauncherVersion': 3,
        'maxLauncherVersion': 100,
        'resources': [ ]
    }

    property string apiKey: ""
    property string apiUrl: "https://api.openai.com/v1/responses"
    property string model: "gpt-4.1"
    
    // Debouncing properties
    property var pendingCallback: null
    property string pendingQuery: ""
    property Timer debounceTimer: Timer {
        interval: 2000 // 3 seconds
        repeat: false
        onTriggered: {
            if (pendingCallback && pendingQuery.length > 0) {
                console.debug("ChatGPT Plugin | Debounce timer triggered, sending request for: " + pendingQuery);
                getChatGPTResponse(pendingQuery, pendingCallback);
                pendingCallback = null;
                pendingQuery = "";
            }
        }
    }

    function init (inputParameter) {
        console.debug("ChatGPT Plugin | Initialized");
    }

    function saveApiKey(key) {
        try {
            apiKey = key;
            console.debug("ChatGPT Plugin | API key saved to property");
            return true;
        } catch (e) {
            console.error("ChatGPT Plugin | Error saving API key: " + e);
            return false;
        }
    }

    function executeInput (inputString, functionId, inputObject) {
        // Handle execution of selected suggestions
        if (functionId === 1) {
            // Open ChatGPT website for more information
            Qt.openUrlExternally("https://chat.openai.com");
        } else if (functionId === 2) {
            // Open OpenAI API keys page
            Qt.openUrlExternally("https://platform.openai.com/api-keys");
        }
    }

    function processInput (inputString, callback, inputObject) {
        console.debug("ChatGPT Plugin | Process input string: " + inputString);
        var suggestions = new Array;
        
        // Check for API key setup command
        if (inputString.toLowerCase().startsWith("chatgpt set key ")) {
            var newApiKey = inputString.substring(16).trim();
            if (newApiKey.length > 0) {
                if (saveApiKey(newApiKey)) {
                    suggestions.push({
                        'label': '<p><b>ChatGPT:</b> ✅ API key saved successfully!</p><p>You can now use ChatGPT by typing "ask", "gpt", "chat", or "ai" followed by your question.</p>'
                    });
                } else {
                    suggestions.push({
                        'label': '<p><b>ChatGPT:</b> ❌ Failed to save API key</p><p>Please try again.</p>'
                    });
                }
            } else {
                suggestions.push({
                    'label': '<p><b>ChatGPT:</b> Please provide an API key</p><p>Usage: "chatgpt set key YOUR_API_KEY"</p>'
                });
            }
            callback(true, suggestions, metadata.id);
            return;
        }

        // Check for help/setup commands
        if (inputString.toLowerCase() === "chatgpt setup" || inputString.toLowerCase() === "chatgpt help" || inputString.toLowerCase() === "chatgpt config") {
            suggestions.push({
                'label': '<p><b>ChatGPT Setup:</b></p><p>1. Get your API key from OpenAI</p><p>2. Type: "chatgpt set key YOUR_API_KEY"</p><p>3. Start asking questions with "ask", "gpt", "chat", or "ai"</p>',
                'functionId': 2
            });
            callback(true, suggestions, metadata.id);
            return;
        }

        // Check if input starts with "gpt", "ask", "chat", or "ai" to trigger ChatGPT
        var triggerWords = ["gpt", "ask", "chat", "ai"];
        var shouldTrigger = false;
        var query = inputString.toLowerCase().trim();
        
        for (var i = 0; i < triggerWords.length; i++) {
            if (query.startsWith(triggerWords[i] + " ") || query === triggerWords[i]) {
                shouldTrigger = true;
                // Remove the trigger word from the query
                if (query.startsWith(triggerWords[i] + " ")) {
                    query = inputString.substring(triggerWords[i].length + 1).trim();
                }
                break;
            }
        }
        
        if (shouldTrigger && query.length > 0) {
            if (apiKey === "") {
                suggestions.push({
                    'label': '<p><b>ChatGPT:</b> 🔑 API key not configured</p><p>Type "chatgpt setup" for instructions</p>',
                    'functionId': 2
                });
                callback(true, suggestions, metadata.id);
                return;
            }
            
            // Stop any existing timer
            debounceTimer.stop();
            
            // Store the query and callback for the debounced execution
            pendingQuery = query;
            pendingCallback = callback;
            
            // Start the debounce timer
            console.debug("ChatGPT Plugin | Starting debounce timer for query: " + query);
            debounceTimer.start();
        } else if (shouldTrigger && query.length === 0) {
            if (apiKey === "") {
                suggestions.push({
                    'label': '<p><b>ChatGPT:</b> 🔑 Setup required</p><p>Type "chatgpt setup" for instructions</p>',
                    'functionId': 2
                });
            } else {
                suggestions.push({
                    'label': '<p><b>ChatGPT:</b> Type your question after "gpt", "ask", "chat", or "ai"</p><p>Example: "ask What is the weather like?"</p>'
                });
            }
            callback(true, suggestions, metadata.id);
        } else {
            callback(true, suggestions, metadata.id);
        }
    }

    function getChatGPTResponse(query, callback) {
        console.debug("ChatGPT Plugin | Making API request for: " + query);
        
        var request = new XMLHttpRequest();
        request.onreadystatechange = function() {
            if (request.readyState === XMLHttpRequest.DONE) {
                console.debug("ChatGPT Plugin | API response status: " + request.status);
                
                if (request.status === 200) {
                    try {
                        var response = JSON.parse(request.responseText);
                        var answer = "";
                        
                        // Parse the new OpenAI API response format
                        if (response && response.output && response.output.length > 0 && 
                            response.output[0].content && response.output[0].content.length > 0) {
                            answer = response.output[0].content[0].text.trim();
                        } else {
                            throw new Error("Unexpected response format");
                        }
                        
                        // Format the response for display
                        var outputString = '<p><b>ChatGPT:</b></p><p>' + escapeHtml(answer) + '</p>';
                        
                        var suggestions = [{
                            'label': outputString,
                            'functionId': 1
                        }];
                        
                        console.debug("ChatGPT Plugin | Response received successfully");
                        callback(true, suggestions, metadata.id);
                    } catch (e) {
                        console.error("ChatGPT Plugin | Error parsing response: " + e);
                        var errorSuggestions = [{
                            'label': '<p><b>ChatGPT:</b> Error parsing response</p><p>Please try again or check your API key.</p>'
                        }];
                        callback(false, errorSuggestions, metadata.id);
                    }
                } else if (request.status === 401) {
                    var errorSuggestions = [{
                        'label': '<p><b>ChatGPT:</b> ❌ Invalid API key</p><p>Type "chatgpt setup" to configure a new key</p>',
                        'functionId': 2
                    }];
                    callback(false, errorSuggestions, metadata.id);
                } else if (request.status === 429) {
                    var errorSuggestions = [{
                        'label': '<p><b>ChatGPT:</b> ⏳ Rate limit exceeded</p><p>Please try again later</p>'
                    }];
                    callback(false, errorSuggestions, metadata.id);
                } else {
                    console.error("ChatGPT Plugin | API error: ", request.status, request.statusText);
                    var errorSuggestions = [{
                        'label': '<p><b>ChatGPT:</b> API error (' + request.status + ')</p><p>Please try again later</p>'
                    }];
                    callback(false, errorSuggestions, metadata.id);
                }
            }
        }
        
        // Prepare the request payload
        var payload = {
            "model": model,
            "instructions": "Provide helpful and concise responses.",
            "input": query
        };
        
        request.open("POST", apiUrl);
        request.setRequestHeader("Content-Type", "application/json");
        request.setRequestHeader("Authorization", "Bearer " + apiKey);
        request.send(JSON.stringify(payload));
    }
    
    function escapeHtml(text) {
        // Basic HTML escaping to prevent issues with special characters
        return text.replace(/&/g, "&amp;")
                  .replace(/</g, "&lt;")
                  .replace(/>/g, "&gt;")
                  .replace(/"/g, "&quot;")
                  .replace(/'/g, "&#39;");
    }
}

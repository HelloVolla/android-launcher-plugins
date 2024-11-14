import QtQuick 2.12;

QtObject {

    property var metadata: {
        'id': 'volla_weather',
        'name': 'Weather Forecast',
        'description': 'It will add feature to get Weather Forecast directly from Springboard',
        'version': 0.3,
        'minLauncherVersion': 3,
        'maxLauncherVersion': 100,
        'resources': [ ]
    }

    property string apiKey: "488297aabb1676640ac7fc10a6c5a2d1"

    function init (inputParameter) {
    }

    function executeInput (inputString, functionId, inputObject) {
console.debug("Weather Plugin | Calling executeInput 1 ")
    }

    function processInput (inputString,  callback, inputObject) {
        // Process the input string here
        // Validate input for city names fpr autocompretion suggestions
        // Return an object containing the autocompletion or interactive live result
        console.debug("Weather Plugin | Process input string: " + inputString)
        var suggestions = new Array
        if (inputObject !== undefined && inputObject.pluginId === metadata.id) {
            var compareStr = inputObject.entity['name'] + ", " + inputObject.entity['state'] +","+ inputObject.entity['country']
        if (inputString.toLowerCase().trim() === compareStr.toLowerCase())
                getWeather(inputObject.entity['name'],inputObject.entity['lat'], inputObject.entity['lon'], callback)
        } else if (inputObject === undefined && inputString.length > 1 && inputString.length < 100) {
            var geoCodingUrl = "http://api.openweathermap.org/geo/1.0/direct?q=" + inputString.replace(/\s+/g,"") + "&limit=5&appid=" + apiKey;
            var locationRequest = new XMLHttpRequest()
            locationRequest.onreadystatechange = function() {
                if (locationRequest.readyState === XMLHttpRequest.DONE) {
                    console.debug("Weather Plugin | Location response: " + locationRequest.status)
                    if (locationRequest.status === 200) {
                        var locations = JSON.parse(locationRequest.responseText)
                        if (locations.length === 1) {
                            getWeather(locations[0].name, locations[0].lat, locations[0].lon, callback)
                        } else {
                            suggestions = [];
                            for (var i = 0; i < locations.length; i++) {
                                var location = locations[i].name
                                if(locations[i].state !== undefined ){
                                    location = location + ", " + locations[i].state
                                }
                                if(locations[i].country !== undefined ){
                                    location = location + ", " + locations[i].country
                                }
                                suggestions.push({'label' : location, 'object': locations[i]});
                                console.log("Weather Plugin | Found location candidate " + location)
                            }
                            console.debug("Weather Plugin | Calling callback true")
                            callback(true, suggestions, metadata.id)
                        }
                    } else {
                        console.error("Weather Plugin | Error retrieving locations: ", locationRequest.status, locationRequest.statusText)
                        callback(false, suggestions, metadata.id)
                    }
                }
            }
            console.debug("Weather Plugin | Calling geoCodingUrl "+geoCodingUrl)
            locationRequest.open("GET", geoCodingUrl)
            locationRequest.send()
        } else {
            callback(true, suggestions, metadata.id);
        }
    }

    function getWeather (location, lat, lon, callback) {
        console.debug("Weather Plugin | Will request weather")
        var weatherUrl = "https://api.openweathermap.org/data/3.0/onecall?lat=" + lat  + "&lon=" + lon + "&units=metric&appid=" + apiKey
        var weatherRequest = new XMLHttpRequest()
        weatherRequest.onreadystatechange = function() {
            if (weatherRequest.readyState === XMLHttpRequest.DONE) {
                console.debug("Weather Plugin | Weather response: " + weatherRequest.status)
                console.debug("Weather Plugin | Weather response: " + weatherRequest.responseText)
                if (weatherRequest.status === 200) {
                    var weather = JSON.parse(weatherRequest.responseText)
                    var weatherIcon = "https://openweathermap.org/img/wn/" + weather.current.weather[0].icon + "@2x.png"
                    console.debug("Weather Plugin | " + weatherIcon, weather.current.temp, weather.current.weather[0].description)
                    var outputString = "<p><img src=\"" + weatherIcon + "\"></p><p>"
                            + weather.current.temp + " °C, " + weather.current.weather[0].description + "</p>"
                    var link = "https://startpage.com/sp/search?query=weather " + location + "&segment=startpage.volla"
                    var suggestions = new Array
                    suggestions.push({'label' : outputString, 'link' : link})
                    console.debug("Weather Plugin | Calling callback true")
                    callback(true, suggestions, metadata.id)
                } else {
                    console.error("Weather Plugin | Error retrieving weather: ", weatherRequest.status, weatherRequest.statusText)
                    callback(false, suggestions, metadata.id)
                }
            }
        }
        weatherRequest.open("GET", weatherUrl)
        weatherRequest.send()
    }
}

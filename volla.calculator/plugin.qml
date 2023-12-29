import QtQuick 2.12;

QtObject {

    property var metadata: {
        'id': 'volla_calculator',
        'name': 'Calculator',
        'description': 'It will add feature to open a calculator directly from Springboard',
        'version': 0.2,
        'minLauncherVersion': 2.3,
        'maxLauncherVersion': 100,
        'resources': [ ]
    }

    function init (inputParameter) {
        // todo: Load city ressouces
    }

    function executeInput (inputString, functionId, inputObject) {
        if (functionId === 0) {
            var parameter = inputObject !== undefined ? "online calculator " + inputObject : "online calculator " + inputString;
            Qt.openUrlExternally("https://startpage.com/sp/search?query=" + encodeURIComponent(parameter) + "&segment=startpage.volla");
        } else {
            console.warn(metadata.id + " | Unknown function " + functionId + " called");
        }
    }

    function processInput (inputString) {
        // Process the input string here
        // Validate input for city names fpr autocompretion suggestions
        // Return an object containing the autocompletion or methods/functions
        var suggestions = new Array;
        if (inputString.length > 1 && inputString.length < 100) {
            suggestions = [{'label' : 'Calculator', 'functionId': 0}];

            if ('Berlin'.startsWith(inputString) && !inputString.startsWith('Berlin')) {
                suggestions.push({'label' : 'Calculator', 'object' : 'Rekenmachine'});
            }
        }
        return suggestions;
    }
}
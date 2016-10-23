document.addEventListener('DOMContentLoaded', function(){
    var eventSource = new EventSource('/live');
    eventSource.onmessage = function (evt) {
        var msg = JSON.parse(evt.data);

        var sensorEl = document.getElementById(msg.id);
        if (sensorEl !== null) {
            var dataEl = sensorEl.querySelector('.sensor-data');
            dataEl.innerHTML = msg.data;
        }
    };
}, false);

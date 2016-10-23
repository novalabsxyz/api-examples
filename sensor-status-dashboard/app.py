#!/usr/bin/env python

from contextlib import closing
from flask import Flask, Response
from flask import render_template
from itertools import islice

import gevent
import gevent.queue
import helium
import json
import os

## SSE encoding
def encode_sse(data):
    if not data:
        return ""
    return "%s: %s\n\n" % ("data", json.dumps(data))


app = Flask(__name__, static_folder='assets')

api_key = os.environ.get('HELIUM_API_KEY')
client = helium.Client(api_key)

@app.route('/')
def index():
    # query list of sensors
    sensors = client.sensors()

    # build a map of sensor information for the templates
    sensor_map = {s.id: {"name": s.name, "id": s.id} for s in sensors}

    # add latest reading to each sensor
    for s in sensors:
        its = s.timeseries(page_size=1, port='t')
        ts = list(islice(its, 1))
        if ts:
            reading = ts[0].value
            if isinstance(reading, float):
                reading = round(reading, 2)
            sensor_map[s.id]['value'] = reading
        else:
            sensor_map[s.id]['value'] = 'n/a'

    template_sensors = sensor_map.values()
    template_sensors.sort(key=lambda x: x['name'])

    return render_template('index.html.j2', sensors=template_sensors)

@app.route('/live')
def live():
    def subscribe(sensor, q):
        timeseries = sensor.timeseries()
        with closing (timeseries.live()) as live:
            for l in live:
                q.put({"id": sensor.id, "data": l.value})

    sensors = client.sensors()
    q = gevent.queue.Queue()

    for s in sensors:
        gevent.spawn(subscribe, s, q)

    def gen():
        try:
            while True:
                e = q.get()
                yield encode_sse(e)
        except GeneratorExit:
            pass
    return Response(gen(), mimetype="text/event-stream")

if __name__ == '__main__':
    # Bind to PORT if defined, otherwise default to 5000.
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port)

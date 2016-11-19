#!/usr/bin/env python

import click
from helium import Client, Sensor
from datetime import datetime
import requests
import logging
from apscheduler.schedulers.background import BlockingScheduler


def _process_weather(api_key, lat, lon, sensor):
    url = str.format("https://api.darksky.net/forecast/{}/{},{}",
                     api_key, lat, lon)
    resp = requests.get(url, params={
        "units": "si",
        "excludes": "minutely,hourly,daily,alerts,flags",
    })
    resp.raise_for_status()
    data = resp.json().get("currently")
    mapping = [
        ("temperature", "t", lambda x: x),     # no conversion (in degC)
        ("humidity", "h", lambda x: 100 * x),  # convert to percentage humidity
        ("pressure", "p", lambda x: 100 * x),  # convert to Pa
    ]
    for path, port, adjust in mapping:
        timestamp = datetime.utcfromtimestamp(data.get('time'))
        value = adjust(data.get(path))
        sensor.timeseries().create(port, value, timestamp=timestamp)

@click.command()
@click.option('--helium-key',
              envvar='HELIUM_API_KEY',
              required=True,
              help='your Helium API key. Can also be specified using the HELIUM_API_KEY environment variable')
@click.option('--darksky-key',
              envvar='DARKSKY_API_KEY',
              required=True,
              help='your darksky.net API key. Can also be specified using the DARKSKY_API_KEY environment variable')
@click.option('--every', type=int, default=60,
              help='how often to monitor (default 60s)')
@click.argument('sensor', type=click.STRING)
@click.argument('lat', type=click.FLOAT)
@click.argument('lon', type=click.FLOAT)
@click.pass_context
def cli(ctx, helium_key, darksky_key, lat, lon, sensor, every):
    """Monitor weather for a lat/lon locaation.

    This sample service shows how you can use an external weather
    service to emit to a virtual sensor in the Helium platform.

    \b
    he-weather  --every <seconds> <sensor> <lat> <lon>

    The given virtual <sensor> is the id of a created Helium virtual
    sensor.

    The optional <seconds> parameter sets how often weather
    information needs to get fetched and posted to Helium. If the
    parameter is not provided a default (60 seconds)) is picked.

    This will run the service based on the given lat/lon.

    """
    client = Client(api_token=helium_key)
    sensor = Sensor.find(client, sensor)

    logging.basicConfig()
    scheduler = BlockingScheduler()
    scheduler.add_job(_process_weather, "interval",
                      seconds=every,
                      next_run_time=datetime.now(),
                      args=[darksky_key, lat, lon, sensor])
    click.echo("Checking every {} seconds".format(every))
    scheduler.start()


if __name__ == '__main__':
    cli()

#!/usr/bin/env python
import helium
import dpath.util as dpath
import click
from datetime import datetime
import yaml
import json
import requests
import logging

class Config():
    def __init__(self, helium_key, forecast_key, geonames_key, config_file="config.yaml"):
        self.service = helium.Service(helium_key)
        self.forecast_key=forecast_key
        self.geonames_key=geonames_key
        self.config_file = config_file

        try:
            self.config = yaml.safe_load(file(config_file, 'r'))
        except:
            self.config = {}

    def add_zip(self, zipcode, **kwargs):
        zipcodes = self.config.setdefault("zipcodes", {})
        zipcodes[zipcode.encode('ascii')] = kwargs
        yaml.dump(self.config, file(self.config_file, 'w'))

    def remove_zip(self, zipcode):
        zipcodes = self.config.setdefault("zipcodes", {})
        zipcodes.pop(zipcode)
        yaml.dump(self.config, file(self.config_file, 'w'))

    def get_zipcode(self, zipcode):
        return self.config.get('zipcodes', {})[zipcode]

    def get_zipcodes(self):
        return self.config.get('zipcodes', {}).iteritems()


pass_config = click.make_pass_decorator(Config)

@click.group()
@click.option('--helium-key',
              envvar='HELIUM_API_KEY',
              required=True,
              help='your Helium API key. Can also be specified using the HELIUM_API_KEY environment variable')
@click.option('--forecast-key',
              envvar='FORECAST_API_KEY',
              required=True,
              help='your forecast.io API key. Can also be specified using the FORECAST_API_KEY environment variable')
@click.option('--geonames-key',
              envvar="GEONAMES_API_KEY",
              help="The user to use for geonames.org zipcode lookup. Can also be specified using the GEONAMES_API_KEY environment variable")
@click.option('--config', default="config.yaml", type=click.Path(),
              help="the configuration file")
@click.pass_context
def cli(ctx, helium_key, forecast_key, geonames_key, config):
    """Monitors weather for one or more zipcodes.

    This sampple service shows how you can create a virtual sensor that emits
    weather related data to the Helium platform.

    Each zipcode is represented as one virtual sensor in Helium.
    A zipcode can be added by running

    \b
    he-weather add <zipcode> --sensor <sensor> --every <seconds>

    Where <zipcode> is the zipcode to monitor. Only US zipcodes are supported
    at this time.

    The given virtual <sensor> is the id of a created Helium
    virtual sensor. If the parameter is not given one will be created and
    will be given a name which includes the zipcode.

    The optional <seconds> parameter sets how often weather information needs to
    get fetched and posted to Helium. If the parameter is not provided a
    default is picked.

    In order to run the service run the following command:

    \b
    he-weather run

    This will run the service based on the configured zipcodes. In order to
    add a zipcode you will need to re-start the service.

    """
    ctx.obj = Config(helium_key, forecast_key, geonames_key, config)


@cli.command()
@click.argument('zipcode')
@click.option('--sensor',
              help="the id of the sensor to post. A new sensor will be created if absent")
@click.option('--every', default=5*60,
              help="Schedule to process the zipcode on. Default is 5 minutes")
@pass_config
def add(config, zipcode, sensor, every):
    """Add a zipcode to be monitored.

    Adds a ZIPCODE to be monitored to the configuration. Note that any running
    instance should be re-started before the addition takes effect.

    The weather data for the given ZIPCODE will be posted to the given SENSOR.
    If the sensor is not provided a new virtual sensor will be created.
    """
    geo_url=str.format("http://api.geonames.org/findNearbyPostalCodesJSON?postalcode={}&country=US&username={}&maxRows=1",
                       zipcode, config.geonames_key)
    resp = requests.get(geo_url)
    resp.raise_for_status()
    json = resp.json()
    lat = dpath.get(json, "postalCodes/[0]/lat")
    lng = dpath.get(json, "postalCodes/[0]/lng")

    if not sensor:
        sensor_data=config.service.create_sensor(name="weather-"+zipcode)
        sensor = dpath.get(sensor_data, "data/id")

    config.add_zip(zipcode.encode('ascii'), sensor=sensor.encode('ascii'), lat=lat, lng=lng, freq=every)
    click.echo(str.format('Added {}', zipcode))


@cli.command()
@click.argument('zipcode')
@pass_config
def remove(config, zipcode):
    """Removes a zipcode from the monitored set
    """
    config.remove_zip(zipcode)
    click.echo(str.format('Removed {}', zipcode))

def _mk_datapoint(json, path, port, adjust):
    value = dpath.get(json, path)
    timestamp = datetime.utcfromtimestamp(dpath.get(json, "time"))
    return {
        "data": {
            "type": "data-point",
            "attributes": {
                "timestamp": timestamp.isoformat() + "Z",
                "port": port,
                "value": adjust(value) if adjust else value
            }
        }
    }

def _fetch_zipcode(config, zipcode, **kwargs):
    forecast_url=str.format("https://api.forecast.io/forecast/{}/{lat},{lng}",
                            config.forecast_key,
                            **config.get_zipcode(zipcode))
    resp = requests.get(forecast_url, params={
        "units": "si",
        "excludes": "minutely,hourly,daily,alerts,flags",
    })
    resp.raise_for_status()
    data = resp.json().get("currently")
    points = [
        ("temperature", "t", None), # no conversion since it's in degC
        ("humidity", "h", lambda x: 100 * x), # convert to percentage humidity
        ("pressure", "p", lambda x: 100 * x), # convert to Pa
    ]
    return [_mk_datapoint(data, path, port, adjust) for path, port, adjust in points]

def _process_zipcode(config, zipcode, **kwargs):
    sensor = kwargs['sensor']
    data = _fetch_zipcode(config, zipcode)
    for reading in data:
        config.service.post_sensor_timeseries(sensor, reading)


@cli.command()
@pass_config
def run(config):
    """Runs the service.

    Runs the weather service for the zipcodes and schedule as given in
    the configuration file.
    """
    from apscheduler.schedulers.background import BlockingScheduler
    logging.basicConfig()
    scheduler = BlockingScheduler()
    for zipcode, info in config.get_zipcodes():
        scheduler.add_job(_process_zipcode, "interval",
                          seconds=info.get("freq", 60),
                          next_run_time=datetime.now(),
                          kwargs=info, args=[config, zipcode])
    scheduler.start()



@cli.command()
@click.argument('zipcode')
@pass_config
def fetch(config, zipcode):
    """Fetch and display zipcode weather.

    This is a utility command to fetch and display weather information as it would
    be submitted to Helium.

    Note: The given zipcode should be already be configured using
    the `add` subcommand
    """
    info = config.get_zipcode(zipcode)
    data = _fetch_zipcode(config, zipcode, **info)
    click.echo(json.dumps(data, indent=4))


if __name__ == '__main__':
    cli()

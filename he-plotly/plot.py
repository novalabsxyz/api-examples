#!/usr/bin/env python
import helium
import helium.commands.timeseries as ts
import dpath.util as dpath
import click
from datetime import datetime
import json
import requests
import plotly.plotly as py
import plotly.graph_objs as graph


class Config():
    def __init__(self, helium_key):
        self.service = helium.Service(helium_key)


pass_config = click.make_pass_decorator(Config)

@click.group()
@click.option('--helium-key',
              envvar='HELIUM_API_KEY',
              help='your Helium API key. Can also be specified using the HELIUM_API_KEY environment variable')
@click.option('--plotly-key',
              envvar='PLOTLY_API_KEY',
              help='your plot.ly API key. Can also be specified using the PLOTLY_API_KEY environment variable')
@click.option('--plotly-user',
              envvar='PLOTLY_API_USER',
              help='your plot.ly API user. Can also be specified using the PLOTLY_API_USER environment variable')
@click.pass_context
def cli(ctx, helium_key, plotly_key, plotly_user):
    """
    """
    if plotly_user and plotly_key:
        py.sign_in(plotly_user, plotly_key)
    ctx.obj = Config(helium_key)

def _str2datetime(str):
    try:
        return datetime.strptime(str, "%Y-%m-%dT%H:%M:%S.%fZ")
    except ValueError:
        return datetime.strptime(str, "%Y-%m-%dT%H:%M:%SZ")

def _plot_data(config, sensor, **kwargs):
    ts_data = config.service.get_sensor_timeseries(sensor, **kwargs).get('data')

    sensor_data = config.service.get_sensor(sensor).get('data')
    sensor_name = dpath.get(sensor_data, "attributes/name")

    timestamps =  dpath.values(ts_data, "*/attributes/timestamp")
    x = [_str2datetime(val) for val in timestamps]
    y = dpath.values(ts_data, "*/attributes/value")

    return graph.Scatter(
        x = x,
        y = y,
        name=sensor_name
    )

@cli.command()
@click.argument('sensor', nargs=-1)
@click.option('--open', is_flag=True,
             help="Whether to open the browser on completion")
@click.option('--sharing', default="secret",
              type=click.Choice(['secret', 'private', 'public']),
              help="Sharing setting for plot.ly")
@click.option('--filename', default="sensor-timeseries",
              help="The plot.ly filename for the resulting plot")
@ts.options()
@pass_config
def plot(config, sensor, **kwargs):
    """
    """
    if not kwargs.get("port"):
        kwargs["port"] = ("t")
    else:
        kwargs["port"] = (kwargs["port"][0])
    ts_port = kwargs["port"][0]

    plot_data = [_plot_data(config, entry, **kwargs) for entry in sensor]

    if len(plot_data) >  1:
        plot_title = "Sensor Timeseries"
    else:
        plot_title = plot_data[0].name

    plot_layout = graph.Layout(
        title = plot_title,
        xaxis = dict(
            title="Time (UTC)"
        ),
        yaxis = dict(
            title=ts_port
        )
    )

    auto_open = kwargs.get("open")
    plot_filename = kwargs.get("filename")
    plot_url = py.plot(graph.Figure(layout=plot_layout, data=plot_data),
                       filename=plot_filename,
                       auto_open=auto_open,
                       sharing=kwargs.get("sharing"))
    click.echo("plot.ly URL: "+ plot_url)
    click.echo("plot.ly file: "+ plot_filename)



if __name__ == '__main__':
    cli()

#!/usr/bin/env python
import helium
import dpath.util as dpath
import click
from datetime import datetime
import plotly.plotly as py
import plotly.graph_objs as graph


class Config():
    def __init__(self, helium_key):
        self.client = helium.Client(api_token=helium_key)


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


def _plot_data(config, sensor, **kwargs):

    sensor = config.client.sensor(sensor)

    timeseries = sensor.timeseries(
        port=kwargs['port'],
        start=kwargs['start'],
        end=kwargs['end'],
        page_size=kwargs['page_size'],
        agg_size=kwargs['agg_size'],
        agg_type=kwargs['agg_type']
        ).take(kwargs['page_size'])

    x = [helium.from_iso_date(dp.timestamp) for dp in timeseries]
    y = [dp.value for dp in timeseries]


    return graph.Scatter(
        x = x,
        y = y,
        name=sensor.name
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
@click.option('--label',
              help="The label id to plot")
@click.option('--port', default='t',
              help="the port to filter readings on")
@click.option('--page-size', default=20,
              help="the number of readings to get per request")
@click.option('--start',
              help="the start date to filter readings on")
@click.option('--end',
              help="the end date to filter readings on")
@click.option('--agg-size',
              help="the time window of the aggregation")
@click.option('--agg-type',
              help="the kinds of aggregations to perform")
@pass_config
def plot(config, sensor, label, **kwargs):
    """Plots a graph.

    Plots a graph for given list of SENSORs or for a specific label if given.
    By default, the number of readings per sensor (`--page-size`) is 20.

    Readings can be filtered by PORT (`t` by default ) and by START and END date.
    Dates are given in ISO-8601 and may be one of the following forms:

    \b
    * YYYY-MM-DD - Example: 2016-05-05
    * YYYY-MM-DDTHH:MM:SSZ - Example: 2016-04-07T19:12:06Z


    Readings can be filtered by PORT and by START and END date and can
    be aggregated given an aggregation type and aggregation window size.

    Dates are given in ISO-8601 and may be one of the following forms:

    \b
    * YYYY-MM-DD - Example: 2016-05-05
    * YYYY-MM-DDTHH:MM:SSZ - Example: 2016-04-07T19:12:06Z

    Aggregations or bucketing of data can be done by specifying
    the size of each aggregation bucket using agg-size
    and one of the size specifiers.

    \b
    Examples: 1m, 2m, 5m, 10m, 30m, 1h, 1d

    How data-points are aggregated is indicated by a list of
    aggregation types using agg-type.

    \b
    Examples: min, max, avg

    For example, max for a specific port 't' and
    aggregate on a daily basis use the following:

    \b
    --agg-type max --agg-size 1d --port t

    """

    if label:
        sensor_list = config.client.label(label).sensors()
        sensor = [sensor.id for sensor in sensor_list]
        if len(sensor) < 1:
            print("No sensors associated with specified label")
            exit(1)

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
            title=kwargs['port']
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

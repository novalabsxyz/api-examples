# Helium plot.ly sample

This example script plots timeseries data for one or more sensors or
all sensors in a label to [plot.ly](https://plot.ly).

For this sample to work you will need an active account at
[plot.ly](https://plot.ly)

To try the sample check out this repo and:

``` shellsession
cd he-plotly
virtualenv env
. env/bin/activate
pip install -r requirements.txt
```

This should install all the requirements in a a virtual environment without
affecting your local setup.

To generate a plot follow the instructions from:

``` shellsession
./plot.py --help
Usage: plot.py [OPTIONS] COMMAND [ARGS]...



Options:
  --helium-key TEXT   your Helium API key. Can also be specified using the
                      HELIUM_API_KEY environment variable
  --plotly-key TEXT   your plot.ly API key. Can also be specified using the
                      PLOTLY_API_KEY environment variable
  --plotly-user TEXT  your plot.ly API user. Can also be specified using the
                      PLOTLY_API_USER environment variable
  --help              Show this message and exit.

Commands:
  plot
```

Note that this script needs your Helium API key, your plot.ly key and user name
which can be retrieved by going to your
[plot.ly profile](https://plot.ly/settings/api)

Once you have them you can set these keys in environment variable:

``` shellsession
export HELIUM_API_KEY=<your helium api key>
export PLOTLY_API_KEY=<your plotly api key>
export PLOTLY_API_USER=<your plotly username>
```

This way you don't have to specify them in every command.

Once set up you ca create a plot for a given sensor or for all sensor under
a label. You can specify start and end-dates, the specific `port` to use and
use the `page-size` parameter to indicate the number of points to plot.

``` shellsession
Usage: plot.py plot [OPTIONS] [SENSOR]...

  Plots a graph.

  Plots a graph for given list of SENSORs or for a specific label if given.
  By default, the number of readings per sensor (`--page-size`) is 20.

  Readings can be filtered by PORT (`t` by default ) and by START and END
  date. Dates are given in ISO-8601 and may be one of the following forms:

  * YYYY-MM-DD - Example: 2016-05-05
  * YYYY-MM-DDTHH:MM:SSZ - Example: 2016-04-07T19:12:06Z

  Readings can be filtered by PORT and by START and END date and can be
  aggregated given an aggregation type and aggregation window size.

  Dates are given in ISO-8601 and may be one of the following forms:

  * YYYY-MM-DD - Example: 2016-05-05
  * YYYY-MM-DDTHH:MM:SSZ - Example: 2016-04-07T19:12:06Z

  Aggregations or bucketing of data can be done by specifying the size of
  each aggregation bucket using agg-size and one of the size specifiers.

  Examples: 1m, 2m, 5m, 10m, 30m, 1h, 1d

  How data-points are aggregated is indicated by a list of aggregation types
  using agg-type.

  Examples: min, max, avg

  For example, max for a specific port 't' and aggregate on a daily basis
  use the following:

  --agg-type max --agg-size 1d --port t

Options:
  --open                          Whether to open the browser on completion
  --sharing [secret|private|public]
                                  Sharing setting for plot.ly
  --filename TEXT                 The plot.ly filename for the resulting plot
  --label TEXT                    The label id to plot
  --port TEXT                     the port to filter readings on
  --page-size INTEGER             the number of readings to get per request
  --start TEXT                    the start date to filter readings on
  --end TEXT                      the end date to filter readings on
  --agg-size TEXT                 the time window of the aggregation
  --agg-type TEXT                 the kinds of aggregations to perform
  --help                          Show this message and exit.
```

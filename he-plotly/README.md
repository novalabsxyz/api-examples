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
./plot.py plot --help
Usage: plot.py plot [OPTIONS] [SENSOR]...

  Plots a graph.

  Plots a graph for given list of SENSORs or for a specific label if given.

  Readings can be filtered by PORT (`t` by default )and by START and END
  date. Dates are given in ISO-8601 and may be one of the following forms:

  * YYYY-MM-DD - Example: 2016-05-05
  * YYYY-MM-DDTHH:MM:SSZ - Example: 2016-04-07T19:12:06Z

Options:
  --open                          Whether to open the browser on completion
  --sharing [secret|private|public]
                                  Sharing setting for plot.ly
  --filename TEXT                 The plot.ly filename for the resulting plot
  --label TEXT                    The label id to plot
  --end TEXT                      the end date to filter readings on
  --start TEXT                    the start date to filter readings on
  --port TEXT                     the port to filter readings on
  --page-size INTEGER             the number of readings to get per request
  --help                          Show this message and exit.

```

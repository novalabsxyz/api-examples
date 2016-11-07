# Sensor Status Dashboard

Requires `npm`, and `python` (tested with Python 2.7).

## Installation

```
$ make
$ export HELIUM_API_KEY='my-api-key'
$ ./env/bin/gunicorn --workers=1 -k gevent app:app
```

Now navigate your browser to [localhost:8000](http://localhost:8000).

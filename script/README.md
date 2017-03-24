# Helium Script Library #

Each of the folders contains a library for the given sensor or Helium
Extension Board. In addition they will contain one or more `main.lua`
files that use the library in a working example, and may contain
helper libraries or utilities that make it easier to use the library
for a given sensor.

## Usage ##

To upload a library to a Helium Atom Development Board during
development, connect the device using a USB cable to your computer and
run one of the given main scripts, combined with the library for the
attached sensor. For example, for the bme280 sensor library:

``` shell
$ helium-script -m main.lua bme280.lua
```

To upload the script to the Atom Development Board so that the Board
can be disconnected from USB and run on attached battery power:

``` shell
$ helium-script -up -m main.lua bme280.lua
```

## Library Documentation ##

The documentation for each sensor library is generated
using [ldoc](http://stevedonovan.github.io/ldoc/) and can be viewed here.

If you'd like to contribute to the documentation install ldoc and run
the following to generate the documentation in the `doc` folder:

``` shell
$ make docs
```

## Additional Docs, and Community ##

* See the [Helium Cloud API documentation](https://dev.helium.com/cloud-api/v1/getting-started/) for all the details on using accessing your data from the cloud.
* See the [Helium Script API documentation](https://dev.helium.com/script-api/getting-started/) for details about the expose APIs in helium-script
* Check out the [helium-script guide](https://dev.helium.com/guides/helium-script/) to learn how to use the helium-script command line tool
* Join us in [chat.helium.com](http://chat.helium.com) if you have any questions. We're standing by to help.

[![Build Status](https://travis-ci.org/atcol/chaos.svg?branch=master)](https://travis-ci.org/squidnyan/chaos)

# chaos

An API, CLI and DSL for event generation & (un)predictable scheduling.

## Motivation

Chaos is an experiment exploring the ideas of a rich event generation DSL combined with parameterising unpredictability
for actions.

The following "core concepts" make up the design & philosophy behind Chaos:

 * an action that encapsulates a side-effect
 * temporal and spatial parameters
 * frequency

## Domain

### Temporal

The `Schedule` type represents the parameters for picking the time of execution
for an action and its two most important value constructors are `Offset` and `Window`. 

`Offset` represents an offset from the point of calculation, e.g. +200ms.

`Window` provides a section of time to randomly pick the point of execution. 

In each case, the general idea is to effectively "describe" the boundaries for
_when_ to run the computation and the API uses this to randomly pick the execution
point.

### Spatial

The `Spatial` type represents the parameters for deciding when to execute an action
based on non-temporal values e.g. a counter, disk space, a random value. The API
supports the `Reader` monad from the `mtl` package for this purpose.

`Spatial` values are ultimately used as the input for mapping to `Schedule` (temporal)
equivalents, as this allows the Chaos API to build a simple parameterised graph 
of execution flow with "simulated" randomness within API-user specific boundaries.

## Examples

There are a number of examples defined in `.chaos` files. See the `examples` folder.

### Offset & randomisation

Execute an action within `[0, 100]` times with a random delay between "now" and 200ms:

    timesIn 100 (Offset 200) (getCurrentTime >>= print)

or asynchronously:

    asyncTimesIn 100 (Offset 200) (getCurrentTime >>= print)

This can also be demonstrated via the CLI:

    atc@atc-xps:~/src/chaos$ ./chaos between --endMs 200 --cmd "echo lol; date"
    lol
    Sat 23 Dec 15:45:41 GMT 2017
    [()]

There is also file-based support:

    every 6 hours {
      ssh my-server "apt-get update -y"
    }

## Building

Once you've cloned, just run with `stack`:

```
stack install
```

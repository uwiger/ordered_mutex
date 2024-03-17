[![Build Status](https://github.com/uwiger/mutex/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/uwiger/mutex/actions/workflows/ci.yml)

# mutex
A gen_server-based lightweight mutex library

This library implements a very lightweight, order-preserving 'mutex'.

The API is:

`mutex:do(Resource:: any(), Fun :: function() -> any()`

The caller may use any resource key to identify the critical section.
As soon as there are no clients in the queue for a resource, that
resource is deleted from the state. As such, the server automatically
garbage-collects the queue system.

On a reasonably modern workstation, the cost of executing the wrapper
is in the neighborhood of 10-20 µs, at least up to 1,000 concurrent callers.
See the eunit test for a simple benchmark setup.

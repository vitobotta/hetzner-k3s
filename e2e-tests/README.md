# End-to-end test harness

This directory contains a few scripts to automate testing of hetzner-k3s across different combinations of configurations.

## How to use this?

Copy `env.sample` to `env` and edit it to indicate your Hetzner API token. You can also change the instance location if you'd like, and the location of the hetzner-k3s binary that you would like to use for testing (convenient if you're building multiple, different versions and want to check for regressions).

Then to run a single test:

```bash
./run-single-test.sh config-sshport-image.yaml IMAGE=ubuntu-22.04 SSHPORT=222
```

The first argument is a configuration file template; the rest of the command line is an optional list of variables to substitute in the template.

To run all the tests:

```bash
./run-all-tests.sh
```

To view test results:

```
./list-test-results.sh
```

The output will look like this:
```
$ ./list-test-results.sh
config-sshport-image.yaml  IMAGE=alma-8 SSHPORT=222           error  creating   test-c59dc574
config-sshport-image.yaml  IMAGE=alma-8 SSHPORT=22            error  creating   test-15c94339
config-sshport-image.yaml  IMAGE=alma-9 SSHPORT=222           ok     tested ok  test-e9acedda
config-sshport-image.yaml  IMAGE=alma-9 SSHPORT=22            ok     tested ok  test-3a378dbe
config-sshport-image.yaml  IMAGE=centos-stream-8 SSHPORT=222  error  done       test-9063a269
config-sshport-image.yaml  IMAGE=centos-stream-8 SSHPORT=22   error  done       test-0a523221
config-sshport-image.yaml  IMAGE=centos-stream-9 SSHPORT=222  ok     done       test-857926a8
config-sshport-image.yaml  IMAGE=debian-11 SSHPORT=222        ok     done       test-fe655f1c
config-sshport-image.yaml  IMAGE=debian-11 SSHPORT=22         ok     tested ok  test-77bf45fe
...
config-sshport-image.yaml  IMAGE=ubuntu-24.04 SSHPORT=222     ok     tested ok  test-b7c132d6
```

## Re-running a test

The test uses a caching system: if you run the same test (same configuration file and same parameters) twice, it will skip it the second time. This is so that you can add a test in the "run-all-tests.sh" script, and re-run it to execute only the new tests that you added.

If you want to re-run a test, delete the corresponding directory: it's the `test-xxxxxxxx` directory shown by `list-test-results.sh`.

## What does it test, exactly?

It executes `hetzner-k3s create`, then executes a few very basic `kubectl` commands, then executes `hetzner-k3s delete`.

Each test is executed in a separate directory (`test-xxxxxxxx` show by `list-test-results.sh`), and the output of each phase is put in a log file in that directory. Status files are also created to track test success or failure.

## That seems very primitive.

It is! The goal was to test if the SSH port option worked correctly across all distros. I thought this could be useful to test other options and combinations of options later.

## It takes a very long time!

Yes, because the tests are executed sequentially, not in parallel. This is because the default Hetzner quotas are fairly low (10 instance, I believe?) and executing more than a couple of tests simultaneously (or in an account that already has a couple of instances running) would exceed the quota and cause the tests to fail.

It would be fairly easy to parallelize the tests if the needs arise, but we should then keep in mind that most folks will have this conservative instance quota, that will cause tests to fail.

## How much will this cost to run?

The instances will only run for a couple of minutes each time. I ran a bunch of tests with a bunch of different configurations and it probably cost me 1-2 EUR, but of course, the size of the instances will influence this; and if you interrupt the test while instances are running (or if it crashes badly enough during the test) some instances might still be running and you will need to clean them up manually!




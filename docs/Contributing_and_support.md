# Contributing and support

Please create a PR if you want to propose any changes, or open an issue if you are having trouble with the tool - I will do my best to help if I can.

If you would like to financially support the project, consider [becoming a sponsor](https://github.com/sponsors/vitobotta).

___
## Building from source

This tool is written in [Crystal](https://crystal-lang.org/). To build it, or to make some changes in the code and try them, you will need to install Crystal locally, or to work in a container.

This repository contains a Dockerfile that builds a container image with Crystal as well as the other required dependencies. There is also a Compose file to conveniently run a container using that image, and mount the source code into the container. Finally, there is a devcontainer file that you can use with compatible IDEs like Visual Studio Code and the Dev Containers extension.


### Developing with VSCode

You need [Visual Studio Code](https://code.visualstudio.com/) and the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers&ssr=false). Open the project in VSCode (for instance, by executing `code .` in the root directory of this git repository). You should see a pop-up dialog prompting you to "Reopen in Container". Do that, then wait until the build is complete and the server has started; then click on "+" to open a terminal inside the container.

Note: if for some reason you can't find the Dev Containers extension in the Marketplace (for instance, if the first result is the Docker extension instead of Dev Containers), check that you have the official build of VSCode. It looks like if you're running an Open Source build, some extensions are disabled.


### Developing with Compose

If you can't or won't install VSCode, you can also develop in the exact same container with Docker and Compose.

To build and run the development container, run:
```bash
docker compose up -d
```

Then, to enter the container:
```bash
docker compose exec hetzner-k3s bash
```


### Inside the container

Once you are inside the dev container (whether you used VSCode or directly Docker Compose), you can run `hetzner-k3s` like this:
```bash
crystal run ./src/hetzner-k3s.cr -- create --config cluster_config.yaml
```

To generate a binary, you can do:
```bash
crystal build ./src/hetzner-k3s.cr --static
```

The `--static` flag will make sure that the resulting binary is statically linked, and doesn't have dependencies on libraries that may or may not be available on the system where you will want to run it.


# Contributing and support

Feel free to create a pull request if you’d like to suggest any changes. If you’re running into issues with the tool, please open an issue, and I’ll do my best to assist you.

If you’re interested in supporting the project financially, you might want to consider [becoming a sponsor](https://github.com/sponsors/vitobotta).

___
## Building from source

This tool is built using [Crystal](https://crystal-lang.org/). If you want to build it or make changes to the code and test them, you’ll need to have Crystal installed on your local machine or use a container.

In this repository, you’ll find a Dockerfile that creates a container image with Crystal and all the necessary dependencies. There’s also a Docker Compose file to easily run a container with that image and link the source code into the container. Additionally, there’s a devcontainer.json file that works with compatible IDEs, such as Visual Studio Code, when using the Dev Containers extension.


### Developing with VSCode

To get started, you’ll need to install [Visual Studio Code](https://code.visualstudio.com/) and the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers&ssr=false). Once you have both, open the project in VSCode. You can do this by running `code .` in the root directory of the git repository.

When the project is open, you should see a pop-up dialog asking you to "Reopen in Container." Go ahead and click that option. Wait for the build process to finish and the server to start. After that, click the "+" button to open a terminal inside the container.

One thing to keep in mind: if you can’t find the Dev Containers extension in the Marketplace (for example, if the first result is the Docker extension instead), make sure you’re using the official build of VSCode. It seems that some extensions are disabled if you’re using an Open Source build.


### Developing with Compose

If you prefer not to install VSCode, you can still develop using Docker and Compose in the exact same container.

To build and start the development container, use this command:
```bash
docker compose up -d
```

After that, to access the container, run:
```bash
docker compose exec hetzner-k3s bash
```

### Working Inside the Container

Once you’re inside the development container (whether through VSCode or Docker Compose directly), you can execute `hetzner-k3s` like this:
```bash
crystal run ./src/hetzner-k3s.cr -- create --config cluster_config.yaml
```

If you want to generate a binary, use this command:
```bash
crystal build ./src/hetzner-k3s.cr --static
```

The `--static` flag ensures the binary is statically linked, meaning it won’t rely on external libraries that might not be available on the system where you plan to run it.

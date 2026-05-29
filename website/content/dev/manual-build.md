---
title: "Build your own image"
---

# Building your own image

If you want to build your own app, you can use the following template:

- Clone the [GOW repo](https://github.com/games-on-whales/gow)

```bash
git clone https://github.com/games-on-whales/gow.git
```

All the published images are in the `apps/` directory.
You can edit any of the images or create a new one.

## Example: edit an already existing image

For example, say that you want to add another emulator to `ES-DE`:

- Edit the `apps/es-de/build/Dockerfile` file and add the necessary software.
- Build the image: open a shell *in the root of the GOW repo*, then use Docker to build with the following command:

```bash
docker build -t gow/es-de:custom --build-arg BASE_APP_IMAGE=ghcr.io/games-on-whales/base-app:edge apps/es-de/build .
```

This will build the image locally with the tag `gow/es-de:custom`.

- Finally, update the `config.toml` file in Wolf to use the new image.
  Just change the `image` field under `[apps.runner]` to the newly locally built `gow/es-de:custom`.
- Don't forget to contribute back by creating a pull request
  in [games-on-whales/gow](https://github.com/games-on-whales/gow)!

{{% details title="I want to edit something in `base` or `base-app`" %}}

Our builds are hierarchical: all images are based on `base-app` which is based on `base`.
You can build them with:

```bash
docker build -t gow/base images/base/build .
docker build -t gow/base-app --build-arg BASE_IMAGE=gow/base images/base-app/build .
```

Now you can use `gow/base-app` as the base image for your custom image.

{{% /details %}}

## Testing on Unraid (Games on Whales plugin)

On Unraid, library bind mounts are applied by the [Games on Whales Unraid plugin](https://github.com/games-on-whales/unraid-plugin) into Wolf's `config.toml` (not only into the Wolf service container). After building Fedora app images locally, use the plugin's `dev-install-test.sh` to wipe, patch `runner.image`, run **Fix mounts**, and verify session mounts. See the plugin's `DEVELOPING.md` section *Clean install with custom GOW images*.
defmodule Mix.Tasks.HexPublishAuto do
  use Mix.Task

  @shortdoc "Publishes package to hex.pm with automatic version bumping"
  @moduledoc """
  Publishes the package to hex.pm with automatic version bumping and git tagging.

  ## Usage

      mix hex_publish_auto [patch|minor|major]

  If no version type is specified, defaults to patch.

  This task will:
  1. Bump the version in mix.exs
  2. Commit the version change
  3. Create a git tag
  4. Build and publish to hex.pm
  5. Push changes and tags to origin

  ## Examples

      mix hex_publish_auto patch    # 0.1.0 -> 0.1.1
      mix hex_publish_auto minor    # 0.1.0 -> 0.2.0
      mix hex_publish_auto major    # 0.1.0 -> 1.0.0
  """

  def run(args) do
    version_type =
      case args do
        [type] when type in ["patch", "minor", "major"] ->
          type

        [] ->
          "patch"

        _ ->
          Mix.shell().error("Invalid version type. Use: patch, minor, or major")
          System.halt(1)
      end

    ensure_clean_working_directory()

    current_version = get_current_version()
    new_version = bump_version(current_version, version_type)

    Mix.shell().info("Bumping version from #{current_version} to #{new_version}")

    update_version_in_mix_file(new_version)

    commit_version_change(new_version)

    create_git_tag(new_version)

    build_and_publish()

    push_to_origin()

    Mix.shell().info("Successfully published version #{new_version} to hex.pm!")
  end

  defp ensure_clean_working_directory do
    {output, status} = System.cmd("git", ["status", "--porcelain"])

    if status != 0 or String.trim(output) != "" do
      Mix.shell().error("Working directory is not clean. Please commit or stash changes first.")
      System.halt(1)
    end
  end

  defp get_current_version do
    mix_file = File.read!("mix.exs")

    case Regex.run(~r/version: "([^"]+)"/, mix_file) do
      [_, version] ->
        version

      nil ->
        Mix.shell().error("Could not find version in mix.exs")
        System.halt(1)
    end
  end

  defp bump_version(version, type) do
    [major, minor, patch] =
      version
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)

    case type do
      "patch" -> "#{major}.#{minor}.#{patch + 1}"
      "minor" -> "#{major}.#{minor + 1}.0"
      "major" -> "#{major + 1}.0.0"
    end
  end

  defp update_version_in_mix_file(new_version) do
    mix_content = File.read!("mix.exs")

    updated_content =
      Regex.replace(~r/version: "[^"]+"/, mix_content, "version: \"#{new_version}\"")

    File.write!("mix.exs", updated_content)
  end

  defp commit_version_change(version) do
    System.cmd("git", ["add", "mix.exs"])
    System.cmd("git", ["commit", "-m", "Bump version to #{version}"])
  end

  defp create_git_tag(version) do
    tag_name = "v#{version}"
    System.cmd("git", ["tag", "-a", tag_name, "-m", "Release #{version}"])
  end

  defp build_and_publish do
    case System.cmd("mix", ["hex.build"]) do
      {_, 0} ->
        Mix.shell().info("Package built successfully")

      {output, _} ->
        Mix.shell().error("Failed to build package: #{output}")
        System.halt(1)
    end

    case System.cmd("mix", ["hex.publish", "--yes"]) do
      {_, 0} ->
        Mix.shell().info("Package published successfully")

      {output, _} ->
        Mix.shell().error("Failed to publish package: #{output}")
        System.halt(1)
    end
  end

  defp push_to_origin do
    System.cmd("git", ["push", "origin", "main"])
    System.cmd("git", ["push", "origin", "--tags"])
  end
end

defmodule ElixosSDK.ImageTest do
  use ExUnit.Case, async: true

  alias ElixosSDK.Image

  @moduletag :tmp_dir

  test "native platforms normalize Docker daemon and OCI architecture spellings" do
    assert Image.native_platform!("linux/x86_64", "linux/amd64", "linux/amd64") ==
             "linux/amd64"

    assert Image.native_platform!("linux/aarch64", "linux/arm64", "linux/arm64") ==
             "linux/arm64"
  end

  test "native SDK and runtime cannot execute through cross-architecture emulation" do
    for {daemon, sdk, runtime} <- [
          {"linux/amd64", "linux/arm64", "linux/arm64"},
          {"linux/arm64", "linux/amd64", "linux/arm64"},
          {"linux/amd64", "linux/amd64", "linux/arm64"}
        ] do
      assert_raise Mix.Error, ~r/require matching Linux Docker daemon/, fn ->
        Image.native_platform!(daemon, sdk, runtime)
      end
    end

    for platform <- ["windows/amd64", "linux/386", "linux/", "amd64"] do
      assert_raise Mix.Error, ~r/require a Linux amd64/, fn ->
        Image.native_platform!(platform, platform, platform)
      end
    end
  end

  test "tag is required and unsupported or ambiguous CLI arguments fail before Docker" do
    assert_raise Mix.Error, ~r/--tag IMAGE is required/, fn -> Image.options!([]) end

    assert_raise OptionParser.ParseError, fn ->
      Mix.Tasks.Elixos.Image.run(["--tag", "app:latest", "--privileged"])
    end

    assert_raise Mix.Error, ~r/Expected mix elixos.image/, fn ->
      Mix.Tasks.Elixos.Image.run(["some-project", "--tag", "app:latest"])
    end

    assert_raise Mix.Error, ~r/--tag may only be supplied once/, fn ->
      Mix.Tasks.Elixos.Image.run(["--tag", "first:latest", "--tag", "second:latest"])
    end

    assert_raise Mix.Error, ~r/Docker image reference/, fn ->
      Image.options!(tag: "app:latest\nRUN unwanted")
    end
  end

  test "repository trust must always be explicit and complete" do
    for options <- [
          [repo: "team"],
          [repo_url: "https://packages.example.org"],
          [repo_key: "/unread-key"],
          [repo: "team", repo_url: "https://packages.example.org"],
          [repo: "team", repo_key: "/unread-key"]
        ] do
      assert_raise Mix.Error, ~r/must be supplied together/, fn ->
        Image.options!([tag: "app:latest"] ++ options)
      end
    end

    assert_raise Mix.Error, ~r/--repo-dir requires/, fn ->
      Image.options!(tag: "app:latest", repo_dir: "/not-a-public-tree")
    end
  end

  test "remote URLs cannot carry host credentials or point at arbitrary host directories" do
    for url <- [
          "https://user:secret@packages.example.org",
          "https://packages.example.org?token=secret",
          "https://packages.example.org#secret",
          "/home/user/private-repository",
          "file:///home/user/private-repository"
        ] do
      assert_raise Mix.Error, ~r/public http\(s\) URL/, fn ->
        Image.options!(
          tag: "app:latest",
          repo: "team",
          repo_url: url,
          repo_key: "/unread-key"
        )
      end
    end
  end

  test "offline mirror URL must be its durable native path" do
    assert_raise Mix.Error, ~r/--repo-url must be \/priv\/hex\/mirrors\/team/, fn ->
      Image.options!(
        tag: "app:latest",
        repo: "team",
        repo_url: "https://silently-ignored.example.org",
        repo_key: "/unread-key",
        repo_dir: "/not-read"
      )
    end
  end

  test "a signing key is rejected on the host before it can enter Docker", %{tmp_dir: directory} do
    key = Path.join(directory, "signing-key.pem")
    File.write!(key, "-----BEGIN RSA PRIVATE KEY-----\nYWJj\n-----END RSA PRIVATE KEY-----\n")

    assert_raise Mix.Error, ~r/never a private key/, fn ->
      Image.options!(
        tag: "app:latest",
        repo: "team",
        repo_url: "https://packages.example.org",
        repo_key: key
      )
    end
  end

  test "offline trees enumerate only public static Hex resources", %{tmp_dir: directory} do
    repository = repository(directory)
    File.write!(Path.join(repository, "packages/example"), "signed package resource")
    File.write!(Path.join(repository, "tarballs/example-0.1.0.tar"), "public source tarball")

    assert Image.repository_files!(repository) == [
             "names",
             "versions",
             "public_key",
             "packages/example",
             "tarballs/example-0.1.0.tar"
           ]

    File.write!(Path.join(repository, "signing-key.pem"), "not public")

    assert_raise Mix.Error, ~r/accepts only a public static Hex tree/, fn ->
      Image.repository_files!(repository)
    end
  end

  test "offline resources cannot smuggle links, private filenames or nested directories", %{
    tmp_dir: directory
  } do
    for {name, prepare} <- [
          {"link",
           fn repository ->
             private = Path.join(Path.dirname(repository), "private")
             File.write!(private, "not public")
             File.ln_s!(private, Path.join(repository, "packages/example"))
           end},
          {"filename",
           fn repository ->
             File.write!(Path.join(repository, "tarballs/signing-key.pem"), "not public")
           end},
          {"directory",
           fn repository ->
             File.mkdir!(Path.join(repository, "packages/example"))
           end}
        ] do
      root = Path.join(directory, name)
      File.mkdir!(root)
      repository = repository(root)
      prepare.(repository)
      assert_raise Mix.Error, fn -> Image.repository_files!(repository) end
    end
  end

  defp repository(directory) do
    repository = Path.join(directory, "public-repository")
    File.mkdir!(repository)
    File.mkdir!(Path.join(repository, "packages"))
    File.mkdir!(Path.join(repository, "tarballs"))

    for resource <- ["names", "versions", "public_key"] do
      File.write!(Path.join(repository, resource), "public resource")
    end

    repository
  end
end

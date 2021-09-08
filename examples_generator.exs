defmodule Ecto.ERD.ExamplesGenerator do
  require Logger

  @shared_examples [
    [name: "Default", formats: [:dbml, :dot, :qdbd]],
    [
      name: "No fields",
      formats: [:dot],
      config: """
      [
        columns: []
      ]
      """
    ],
    [
      name: "Contexts as clusters",
      formats: [:dbml, :dot],
      config: """
      alias Ecto.ERD.Node

      [
        map_node: fn
          %Node{schema_module: schema_module} = node ->
            node |> Node.set_cluster(schema_module |> Module.split() |> Enum.take(2) |> Enum.join("."))
        end
      ]
      """
    ],
    [
      name: "Contexts as clusters (no fields)",
      formats: [:dot],
      config: """
      alias Ecto.ERD.Node

      [
        columns: [],
        map_node: fn
          %Node{schema_module: schema_module} = node ->
            node |> Node.set_cluster(schema_module |> Module.split() |> Enum.take(2) |> Enum.join("."))
        end
      ]
      """
    ]
  ]

  @data %{
    "papercups" => %{
      repo: "git@github.com:papercups-io/papercups.git",
      examples: @shared_examples
    },
    "plausible-analytics" => %{
      repo: "git@github.com:plausible/analytics.git",
      examples: @shared_examples
    },
    "changelog.com" => %{
      repo: "git@github.com:thechangelog/changelog.com.git",
      examples:
        Enum.filter(@shared_examples, fn example -> example[:name] in ["Default", "No fields"] end) ++
          [
            [
              name: "Clusters",
              formats: [:dbml, :dot],
              config: """
              alias Ecto.ERD.Node

              [
                map_node: fn
                  %Node{schema_module: schema_module} = node ->
                    cluster_name =
                      cond do
                        schema_module in [
                          Changelog.Episode,
                          Changelog.EpisodeGuest,
                          Changelog.EpisodeHost,
                          Changelog.EpisodeRequest,
                          Changelog.EpisodeSponsor,
                          Changelog.EpisodeStat,
                          Changelog.EpisodeTopic
                        ] ->
                          "EPISODE"

                        schema_module in [Changelog.Post, Changelog.PostTopic] ->
                          "POST"

                        schema_module in [Changelog.Podcast, Changelog.PodcastHost, Changelog.PodcastTopic] ->
                          "PODCAST"

                          schema_module in [
                            Changelog.EpisodeNewsItem,
                            Changelog.NewsAd,
                            Changelog.NewsIssue,
                            Changelog.NewsIssueAd,
                            Changelog.NewsIssueItem,
                            Changelog.NewsItem,
                            Changelog.NewsItemComment,
                            Changelog.NewsItemTopic,
                            Changelog.NewsQueue,
                            Changelog.NewsSource,
                            Changelog.NewsSponsorship,
                            Changelog.PostNewsItem
                          ] -> "NEWS"

                        true ->
                          nil
                      end

                    Node.set_cluster(node, cluster_name)
                end
              ]
              """
            ]
          ]
    },
    "conduit" => %{
      repo: "git@github.com:slashdotdash/conduit.git",
      examples: @shared_examples
    },
    "hexpm" => %{
      repo: "git@github.com:hexpm/hexpm.git",
      examples:
        @shared_examples ++
          [
            [
              name: "Only selected cluster (Accounts context)",
              formats: [:dbml, :dot, :qdbd],
              config: """
              alias Ecto.ERD.Node

              [
                map_node: fn
                  %Node{schema_module: schema_module} = node ->
                    cluster_name = schema_module |> Module.split() |> Enum.take(2) |> Enum.join(".")
                    case cluster_name do
                      "Hexpm.Accounts" -> node |> Node.set_cluster(cluster_name)
                      _ -> nil
                    end
                end
              ]
              """
            ],
            [
              name: "Only embedded schemas",
              formats: [:dot],
              config: """
              alias Ecto.ERD.Node

              [
                map_node: fn
                  %Node{source: nil} = node -> node
                  _ -> nil
                end
              ]
              """
            ]
          ]
    }
  }

  def run(source_url_root) do
    File.mkdir_p("tmp/docs")
    File.mkdir_p("examples/dot_images")
    File.mkdir_p("examples/dbml")
    File.mkdir_p("examples/quick_dbd")
    File.mkdir("tmp/repos")
    File.mkdir("tmp/dot")
    File.mkdir("tmp/config_files")

    @data
    |> Enum.each(fn {project_name, %{repo: repo, examples: examples}} = data_item ->
      File.mkdir(Path.join("examples/dot_images", project_name))
      File.mkdir(Path.join("examples/dbml", project_name))
      File.mkdir(Path.join("examples/quick_dbd", project_name))
      File.mkdir(Path.join("tmp/dot", project_name))
      File.mkdir(Path.join("tmp/config_files", project_name))
      init_project(project_name, repo)

      examples
      |> Enum.map(fn example -> Task.async(fn -> generate_example(example, project_name) end) end)
      |> Task.yield_many(:infinity)

      generate_doc(data_item, source_url_root)
    end)
  end

  defp generate_doc({project_name, %{repo: repo, examples: examples}}, source_url_root) do
    examples_md =
      examples
      |> Enum.map_join("\n\n", fn example ->
        config_content =
          if example[:config] do
            """
            #### Config file

            ```elixir
            # .ecto_erd.exs
            #{example[:config]}
            ```
            """
          end

        links_to_output =
          example[:formats]
          |> Enum.map(fn
            :dbml ->
              url =
                Path.join([
                  source_url_root,
                  "examples/dbml",
                  project_name,
                  slugify(example[:name]) <> ".dbml"
                ])

              "DBML: [View document on GitHub](#{url})"

            :qdbd ->
              url =
                Path.join([
                  source_url_root,
                  "examples/quick_dbd",
                  project_name,
                  slugify(example[:name]) <> ".qdbd"
                ])

              "QuickDBD: [View document on GitHub](#{url})"

            :dot ->
              url =
                Path.join([
                  source_url_root,
                  "examples/dot_images",
                  project_name,
                  slugify(example[:name]) <> ".png"
                ])

              "DOT: [View image on GitHub](#{url})"
          end)

        output_content = """
        #### Output

        #{Enum.join(links_to_output, "\n\n")}
        """

        """
        ## #{example[:name]}

        #{output_content}

        #{config_content}
        """
      end)

    content = """
    # #{project_name}

    Repo: `#{repo}`

    #{examples_md}
    """

    File.write!(Path.join("tmp/docs", project_name <> ".md"), content)
  end

  defp generate_example(example, project_name) do
    Logger.debug("#{project_name}: generating #{example[:name]}")
    slug = slugify(example[:name])

    example[:formats]
    |> Enum.map(fn
      :dot -> {:dot, Path.expand(Path.join(["tmp/dot", project_name, slug <> ".dot"]))}
      :dbml -> {:dbml, Path.expand(Path.join(["examples/dbml", project_name, slug <> ".dbml"]))}
      :qdbd -> {:qdbd, Path.expand(Path.join(["examples/quick_dbd", project_name, slug <> ".qdbd"]))}
    end)
    |> Enum.each(fn {format, output_path} ->
      if example[:config] do
        config_path = Path.expand(Path.join(["tmp/config_files", project_name, slug <> ".exs"]))
        File.write!(config_path, example[:config])

        System.cmd(
          "mix",
          [
            "ecto.gen.erd",
            "--output-path=#{output_path}",
            "--config-path=#{config_path}"
          ],
          cd: Path.join("tmp/repos", project_name),
          stderr_to_stdout: true
        )
      else
        System.cmd("mix", ["ecto.gen.erd", "--output-path=#{output_path}"],
          cd: Path.join("tmp/repos", project_name),
          stderr_to_stdout: true
        )
      end

      if format == :dot do
        System.cmd(
          "dot",
          [
            "-Tpng",
            output_path,
            "-o",
            Path.join(["examples/dot_images", project_name, slug <> ".png"])
          ],
          stderr_to_stdout: true
        )
      end
    end)

    Logger.debug("#{project_name}: generated #{example[:name]}")
  end

  defp init_project(project_name, repo) do
    Logger.debug("#{project_name}: clone repo")
    System.cmd("git", ["clone", repo, project_name], cd: "tmp/repos", stderr_to_stdout: true)
    add_ecto_erd_to_dependencies(Path.join(["tmp/repos", project_name, "mix.exs"]))
    Logger.debug("#{project_name}: get dependencies")

    System.cmd("mix", ["deps.get"],
      cd: Path.join("tmp/repos", project_name),
      stderr_to_stdout: true
    )

    Logger.debug("#{project_name}: compile")

    System.cmd("mix", ["compile"],
      cd: Path.join("tmp/repos", project_name),
      stderr_to_stdout: true
    )
  end

  defp slugify(name) do
    name |> String.replace(~r/\s+/, "-") |> String.replace(~r/[^\w-]+/, "")
  end

  defp add_ecto_erd_to_dependencies(path) do
    dependency_line = inspect({:ecto_erd, path: "../../../"})
    content = File.read!(path)

    if String.contains?(content, dependency_line) do
      Logger.debug("#{dependency_line} already present in #{path}")
    else
      new_content =
        content
        |> String.replace(~r|defp? deps(?:\(\))? do\n( +)\[|, ~s|\\0\n\\1  #{dependency_line},|)

      File.write!(path, new_content)
      Logger.debug("Added #{dependency_line} to #{path}")
    end
  end

  def projects, do: Map.keys(@data)
end

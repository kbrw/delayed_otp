defmodule DelayedOTP.Mixfile do
  use Mix.Project

  def project do
    [app: :delayed_otp,
     version: "0.0.2",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     package: [
       maintainers: ["Arnaud Wetzel"],
       licenses: ["MIT"],
       links: %{
         "GitHub" => "https://github.com/awetzel/delayed_otp"
       }
     ],
     description: """
     Delay death of supervisor children or gen_server : for instance
     Erlang supervisor with exponential backoff restart strategy.
     """,
     deps: []]
  end

  def application do
    [applications: [:logger]]
  end
end

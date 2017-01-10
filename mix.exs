defmodule DelayedOTP.Mixfile do
  use Mix.Project

  def project do
    [app: :delayed_otp,
     version: "0.0.3",
     elixir: ">= 1.2.0",
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
     deps: [{:ex_doc, ">= 0.0.0", only: :dev}]]
  end

  def application do
    [applications: [:logger]]
  end
end

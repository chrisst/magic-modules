# api.yaml generator

This is a tool designed to generate a Magic Modules api.yaml from a discovery doc.
It can be run to generate a single or list of Resources per discovery doc. The api.yaml
formatted object will be output to standard out and can be redirected to a file.

## How to run
The entrypoint is `tools/generator/run.rb` and to view flags/usage pass the `--help` flag.

Common example of usage:
`ruby tools/generator/run.rb -t Disk -u https://www.googleapis.com/discovery/v1/apis/compute/v1/rest`
`ruby tools/generator/run.rb -t Realm,GameServerDeployment -u http://localhost:8080/gameservices_service.json  -p resources.projects.resources.locations.resources`

# Kamatera RKE2 End to End integration tests

github workflow runs a matrix of tests, see .github/workflows/ci.yaml for details and how to run locally

The tests don't cleanup on failure, so to cleanup everything for any created clusters, run the following for all datacenters used in tests:

```
kamatera-rke2-kubernetes-terraform-example-tests destroy --name-prefix kca --datacenter-id IL,US-NY2,EU
```

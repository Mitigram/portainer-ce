# Easily Configurable Portainer (CE Edition)

This project creates a [portainer] Docker image that can be configured through a
combination of environment variables (starting with `PORTAINER_`), JSON file and
command-line options. In addition, the project provides ways to initialise teams
and users. Team creation facilitates matching between LDAP groups and Portainer
teams, whenever LDAP is used to automatically create users and associate them to
existing teams.

## Implementation Notes

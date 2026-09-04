SCRIPTS — plain English
=======================

Think of these as helpers. Terraform builds the platform.
These scripts are for setup checks and pausing/resuming to save money.


1) bootstrap-state.sh

   Problem it solves:
     Terraform needs somewhere to store its state files.
     That place is an S3 bucket + a DynamoDB lock table.

   When to run:
     Once, before you ever run "terraform init".
     You already did this for this account — do not run it again
     unless you start in a brand-new AWS account.


2) validate-helm.sh

   Problem it solves:
     Checks that your Helm chart and values files are valid.
     It only checks. It does not install or change the cluster.

   When to run:
     After you edit files under helm/ or helm-values/.
     Before you let Argo CD deploy the apps.


3) env-status.sh

   Problem it solves:
     Answers: "Is my env on or off right now?"
     (Are the nodes running? Is the database running?)

   When to run:
     Anytime you want a quick look.
     Example: ./scripts/env-status.sh dev


4) stop-env.sh

   Problem it solves:
     Turns the env mostly off so you stop paying for nodes + database.
     (EKS control plane stays on; that small cost remains.)

   When to run:
     When you are done for the day / week and will not use the env.
     Example: ./scripts/stop-env.sh dev


5) start-env.sh

   Problem it solves:
     Turns the env back on after you used stop-env.sh.

   When to run:
     When you need to work on the env again.
     Example: ./scripts/start-env.sh dev


Typical order after the platform exists
--------------------------------------
  Work on apps  →  validate-helm.sh
  Done for now  →  stop-env.sh
  Back to work  →  start-env.sh
  Not sure?     →  env-status.sh

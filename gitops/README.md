```
MoongCheap-Cloud/
└── gitops/
    ├── charts/
    │   └── moongcheap-service/
    │       ├── Chart.yaml
    │       ├── values.yaml
    │       └── templates/
    │
    ├── environments/
    │   ├── dev/
    │   │   ├── frontend.yaml
    │   │   ├── backend.yaml
    │   │   └── ai.yaml
    │   └── prod/
    │       ├── frontend.yaml
    │       ├── backend.yaml
    │       └── ai.yaml
    │
    ├── argocd/
    │   ├── applicationset-dev.yaml
    │   └── applicationset-prod.yaml
    │
    └── README.md
    ```
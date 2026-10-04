{{ range $i, $m := .Manifests }}
{{ if eq $m.kind "Deployment" }}
{{ $name := dig "metadata" "annotations" "k8s.score.dev/workload-name" "" $m }}
{{ $workload := index $.Workloads $name }}
{{ $revision := dig "metadata" "revision" "" $workload }}
- op: set
  path: {{ $i }}.metadata.labels.kubedeploy\.io/part-of
  value: demo
- op: set
  path: {{ $i }}.metadata.labels.app\.kubernetes\.io/version
  value: {{ print "sha-" $revision | quote }}
- op: set
  path: {{ $i }}.metadata.annotations.kubedeploy\.io/source-revision
  value: {{ $revision | quote }}
- op: set
  path: {{ $i }}.spec.template.metadata.labels.kubedeploy\.io/part-of
  value: demo
- op: set
  path: {{ $i }}.spec.template.metadata.labels.app\.kubernetes\.io/version
  value: {{ print "sha-" $revision | quote }}
- op: set
  path: {{ $i }}.spec.template.spec.automountServiceAccountToken
  value: false
- op: set
  path: {{ $i }}.spec.template.spec.securityContext
  value:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
{{ range $cname, $_ := $m.spec.template.spec.containers }}
- op: set
  path: {{ $i }}.spec.template.spec.containers.{{ $cname }}.securityContext
  value:
    allowPrivilegeEscalation: false
    privileged: false
    capabilities:
      drop: ["ALL"]
{{ end }}
{{ end }}
{{ end }}

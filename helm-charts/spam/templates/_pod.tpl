{{- define "spam.pod" -}}
{{- $root := . -}}
{{- with .Values.schedulerName }}
schedulerName: "{{ . }}"
{{- end }}
serviceAccountName: {{ include "spam.serviceAccountName" . }}
automountServiceAccountToken: {{ .Values.automountServiceAccountToken }}
{{- with .Values.securityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.priorityClassName }}
priorityClassName: {{ . }}
{{- end }}
{{- if ( or .Values.initChownData.enabled .Values.extraInitContainers) }}
initContainers:
{{- end }}
{{- if .Values.initChownData.enabled }}
  - name: init-chown-data
    {{- $registry := .Values.global.imageRegistry | default .Values.initChownData.image.registry -}}
    {{- if .Values.initChownData.image.sha }}
    image: "{{ $registry }}/{{ .Values.initChownData.image.repository }}:{{ .Values.initChownData.image.tag }}@sha256:{{ .Values.initChownData.image.sha }}"
    {{- else }}
    image: "{{ $registry }}/{{ .Values.initChownData.image.repository }}:{{ .Values.initChownData.image.tag }}"
    {{- end }}
    imagePullPolicy: {{ .Values.initChownData.image.pullPolicy }}
    {{- with .Values.initChownData.securityContext }}
    securityContext:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    command:
      - chown
      - -R
      - {{ .Values.securityContext.runAsUser }}:{{ .Values.securityContext.runAsGroup }}
      - /usr/src/app
    {{- with .Values.initChownData.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    volumeMounts:
      - name: app-data
        mountPath: "/usr/src/app"
{{- end }}
{{- if or .Values.image.pullSecrets .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- include "spam.imagePullSecrets" (dict "root" $root "imagePullSecrets" .Values.image.pullSecrets) | nindent 2 }}
{{- end }}
containers:
  - name: spam
    {{- $registry := .Values.global.imageRegistry | default .Values.image.registry -}}
    {{- if .Values.image.sha }}
    image: "{{ $registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}@sha256:{{ .Values.image.sha }}"
    {{- else }}
    image: "{{ $registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
    {{- end }}
    imagePullPolicy: {{ .Values.image.pullPolicy }}
    {{- if .Values.command }}
    command:
    {{- range .Values.command }}
      - {{ . | quote }}
    {{- end }}
    {{- end }}
    {{- if .Values.args }}
    args:
    {{- range .Values.args }}
      - {{ . | quote }}
    {{- end }}
    {{- end }}
    {{- with .Values.containerSecurityContext }}
    securityContext:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    ports:
      - name: {{ .Values.podPortName }}
        containerPort: {{ .Values.service.targetPort }}
        protocol: TCP
    {{- with .Values.env }}
    env:
      {{- range $key, $value := . }}
      - name: "{{ tpl $key $ }}"
        value: "{{ tpl (print $value) $ }}"
      {{- end }}
    {{- end }}
    {{- with .Values.livenessProbe }}
    livenessProbe:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.readinessProbe }}
    readinessProbe:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- tpl (toYaml .) $root | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

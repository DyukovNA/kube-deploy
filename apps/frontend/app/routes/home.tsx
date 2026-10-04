import { zodResolver } from "@hookform/resolvers/zod";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { z } from "zod";
import { Button } from "~/components/ui/button";
import { api } from "~/lib/api";

const formSchema = z.object({
  text: z.string().trim().min(1, "Введите сообщение").max(280, "Не более 280 символов"),
});

type FormValues = z.infer<typeof formSchema>;

export function meta() {
  return [
    { title: "KubeDeploy — журнал развертывания" },
    { name: "description", content: "Локальная доска сообщений для демонстрации KubeDeploy Platform" },
  ];
}

export default function Home() {
  const queryClient = useQueryClient();
  const [announcement, setAnnouncement] = useState("");
  const version = useQuery({ queryKey: ["version"], queryFn: api.version });
  const health = useQuery({ queryKey: ["health"], queryFn: api.ready, refetchInterval: 30_000 });
  const messages = useQuery({ queryKey: ["messages"], queryFn: api.messages });
  const form = useForm<FormValues>({ resolver: zodResolver(formSchema), defaultValues: { text: "" } });
  const messageText = useWatch({ control: form.control, name: "text" });
  const create = useMutation({
    mutationFn: (text: string) => api.create(text),
    onSuccess: async () => {
      form.reset();
      setAnnouncement("Сообщение сохранено");
      await queryClient.invalidateQueries({ queryKey: ["messages"] });
    },
    onError: () => setAnnouncement("Не удалось сохранить сообщение. Повторите попытку."),
  });

  const healthy = health.isSuccess;
  const statusLabel = health.isPending ? "Проверка" : healthy ? "Система готова" : "API недоступен";

  return (
    <div className="app-shell">
      <aside className="status-rail" aria-label="Статус платформы">
        <div className="rail-brand"><span className="brand-mark" aria-hidden="true">K/</span><span>KUBEDEPLOY<br />PLATFORM</span></div>
        <div className="rail-main">
          <p className="eyebrow rail-label">LOCAL ENVIRONMENT / 01</p>
          <div className="signal-block"><span className={`signal-dot ${healthy ? "is-live" : ""}`} aria-hidden="true" /><span>{statusLabel}</span></div>
          <p className="rail-copy">Системная конфигурация под контролем Git. Приложение живёт в локальном Kubernetes.</p>
          <div className="rail-rule" />
          <div className="rail-stat"><span>Кластер</span><strong>k3d / local</strong></div>
          <div className="rail-stat"><span>Хранилище</span><strong>PostgreSQL</strong></div>
          <div className="rail-stat"><span>Доставка</span><strong>Score → K8s</strong></div>
        </div>
        <p className="rail-foot">GitOps / Policy as Code / Repeatable Delivery</p>
      </aside>

      <main className="content">
        <header className="topbar">
          <span className="topbar-path">PLATFORM / APPLICATION / MESSAGES</span>
          <span className="topbar-date">DEMO WORKLOAD · 001</span>
        </header>
        <section className="intro" aria-labelledby="page-title">
          <div>
            <p className="eyebrow">WORKLOAD STATUS / LIVE</p>
            <h1 id="page-title">Журнал<br /><em>развёртывания.</em></h1>
            <p className="intro-copy">Каждое сообщение проходит через frontend, Go API и PostgreSQL. Обновление версии не стирает историю.</p>
          </div>
          <div className="version-card">
            <span className="version-card-label">ТЕКУЩАЯ ВЕРСИЯ</span>
            <strong>{version.isSuccess ? version.data.version || "local" : version.isPending ? "Загрузка…" : "Недоступна"}</strong>
            <span className="version-sha">{version.isSuccess ? version.data.commit || "unversioned" : "—"}</span>
          </div>
        </section>

        <div className="section-divider"><span>01 / СООБЩЕНИЯ</span><span>{messages.isSuccess ? String(messages.data.length).padStart(2, "0") : "—"} ЗАПИСЕЙ</span></div>
        <div className="workspace">
          <section className="feed" aria-labelledby="feed-title">
            <div className="panel-heading"><h2 id="feed-title">Лента событий</h2><Button tone="quiet" type="button" onClick={() => void messages.refetch()} disabled={messages.isFetching}>Обновить ↗</Button></div>
            {messages.isPending && <div className="feed-state">Загружаем сообщения…</div>}
            {messages.isError && <div className="feed-state feed-error"><p>Связь с API прервана.</p><Button type="button" onClick={() => void messages.refetch()}>Повторить</Button></div>}
            {messages.isSuccess && messages.data.length === 0 && <div className="feed-state empty-state"><span className="empty-glyph" aria-hidden="true">✳</span><p>Здесь пока тихо.</p><span>Оставьте первое сообщение — оно сохранится в PostgreSQL.</span></div>}
            {messages.isSuccess && messages.data.length > 0 && <ol className="message-list">{messages.data.map((message) => <li key={message.id} className="message"><div className="message-meta"><span>#{String(message.id).padStart(3, "0")}</span><time dateTime={message.createdAt}>{new Date(message.createdAt).toLocaleString("ru-RU", { dateStyle: "medium", timeStyle: "short" })}</time></div><p>{message.text}</p></li>)}</ol>}
            {messages.isFetching && !messages.isPending && <p className="refresh-note">Обновляем ленту…</p>}
          </section>

          <section className="compose" aria-labelledby="compose-title">
            <div className="compose-index">02 / НОВАЯ ЗАПИСЬ</div>
            <h2 id="compose-title">Оставить<br />отметку</h2>
            <p>Короткое сообщение станет частью истории этого развёртывания.</p>
            <form onSubmit={form.handleSubmit((values) => create.mutate(values.text))} noValidate>
              <label htmlFor="message-text">Сообщение</label>
              <textarea id="message-text" rows={5} maxLength={280} placeholder="Что изменилось сегодня?" aria-invalid={!!form.formState.errors.text} aria-describedby="message-help message-error" {...form.register("text")} />
              <div className="field-footer"><span id="message-help">До 280 символов</span><span>{[...messageText].length} / 280</span></div>
              <p className="field-error" id="message-error" role="alert">{form.formState.errors.text?.message}</p>
              <Button type="submit" disabled={create.isPending}>{create.isPending ? "Сохраняем…" : "Опубликовать ↗"}</Button>
              {create.isError && <p className="submit-error" role="alert">Не удалось сохранить. Проверьте соединение и повторите.</p>}
            </form>
          </section>
        </div>
        <footer className="page-foot"><span>KUBEDEPLOY / DEMO APPLICATION</span><span>GIT → BUILD → VERIFY → DEPLOY</span></footer>
        <div className="sr-only" role="status" aria-live="polite">{messages.isError ? "Не удалось загрузить сообщения" : announcement}</div>
      </main>
    </div>
  );
}

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Links, Meta, Outlet, Scripts, ScrollRestoration } from "react-router";
import type { LinksFunction } from "react-router";
import stylesheet from "./styles.css?url";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: 1, staleTime: 15_000, refetchOnWindowFocus: false },
  },
});

export const links: LinksFunction = () => [{ rel: "stylesheet", href: stylesheet }];

export function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ru">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Meta />
        <Links />
      </head>
      <body>
        {children}
        <ScrollRestoration />
        <Scripts />
      </body>
    </html>
  );
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <Outlet />
    </QueryClientProvider>
  );
}

export function HydrateFallback() {
  return <div className="initial-shell">Загрузка пульта развёртывания…</div>;
}

export function ErrorBoundary() {
  return (
    <main className="fatal-error">
      <p className="eyebrow">SYSTEM / ERROR</p>
      <h1>Экран временно недоступен</h1>
      <p>Попробуйте обновить страницу. Уже сохранённые сообщения останутся в PostgreSQL.</p>
      <a href="/">Вернуться на главную</a>
    </main>
  );
}

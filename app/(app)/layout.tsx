import { AppDataProvider } from "@/components/app-data";
import { AssistantProvider } from "@/components/assistant/assistant-provider";
import { Sidebar, TabBar } from "@/components/tabbar";
import { ToastProvider } from "@/components/toast";

export default function AppLayout({ children }: LayoutProps<"/">) {
  return (
    <ToastProvider>
      <AppDataProvider>
        <AssistantProvider>
          <Sidebar />
          <main className="app-main pb-tabbar">{children}</main>
          <TabBar />
        </AssistantProvider>
      </AppDataProvider>
    </ToastProvider>
  );
}

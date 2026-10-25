import { AppDataProvider } from "@/components/app-data";
import { AiPanel } from "@/components/assistant/ai-panel";
import { AssistantProvider } from "@/components/assistant/assistant-provider";
import { Sidebar, TabBar } from "@/components/tabbar";
import { Haptics } from "@/components/haptics";
import { ToastProvider } from "@/components/toast";

export default function AppLayout({ children }: LayoutProps<"/">) {
  return (
    <ToastProvider>
      <AppDataProvider>
        <AssistantProvider>
          <Sidebar />
          <main className="app-main pb-tabbar">{children}</main>
          <TabBar />
          <AiPanel />
          <Haptics />
        </AssistantProvider>
      </AppDataProvider>
    </ToastProvider>
  );
}

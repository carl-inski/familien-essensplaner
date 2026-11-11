import { AppDataProvider } from "@/components/app-data";
import { AiPanel } from "@/components/assistant/ai-panel";
import { AssistantProvider } from "@/components/assistant/assistant-provider";
import { DecideInvite } from "@/components/decide/invite-banner";
import { DetailSheets } from "@/components/detail-sheets";
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
          <DetailSheets />
          <DecideInvite />
          <Haptics />
        </AssistantProvider>
      </AppDataProvider>
    </ToastProvider>
  );
}

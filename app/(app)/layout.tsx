import { AppDataProvider } from "@/components/app-data";
import { Sidebar, TabBar } from "@/components/tabbar";
import { ToastProvider } from "@/components/toast";

export default function AppLayout({ children }: LayoutProps<"/">) {
  return (
    <ToastProvider>
      <AppDataProvider>
        <Sidebar />
        <main className="app-main pb-tabbar">{children}</main>
        <TabBar />
      </AppDataProvider>
    </ToastProvider>
  );
}

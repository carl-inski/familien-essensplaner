import { AppDataProvider } from "@/components/app-data";
import { TabBar } from "@/components/tabbar";
import { ToastProvider } from "@/components/toast";

export default function AppLayout({ children }: LayoutProps<"/">) {
  return (
    <ToastProvider>
      <AppDataProvider>
        <main className="pb-tabbar">{children}</main>
        <TabBar />
      </AppDataProvider>
    </ToastProvider>
  );
}

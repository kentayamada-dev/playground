export const readParams = async ({ params }: LayoutProps<"/">): Promise<string> => {
  const resolved = await params;
  return JSON.stringify(resolved);
};

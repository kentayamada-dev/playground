export const readParams = async ({ params }: LayoutProps<"/">): Promise<string> => {
  const value = await params;
  return JSON.stringify(value);
};

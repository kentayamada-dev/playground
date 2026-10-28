const wait = async (): Promise<void> => {
  await Promise.resolve();
};

export const run = (): void => {
  wait();
};
